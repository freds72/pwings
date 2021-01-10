import sys
import os
import io
import re
import math
import logging
import argparse
from antlr4 import *
from collections import namedtuple
from dotdict import dotdict
from PIL import Image, ImageFilter
from lzs import *
from python2pico import to_cart
from python2pico import pack_variant

# RGB to pico8 color index
rgb_to_pico8={
  "0x000000":0,
  "0x1d2b53":1,
  "0x7e2553":2,
  "0x008751":3,
  "0xab5236":4,
  "0x5f574f":5,
  "0xc2c3c7":6,
  "0xfff1e8":7,
  "0xff004d":8,
  "0xffa300":9,
  "0xffec27":10,
  "0x00e436":11,
  "0x29adff":12,
  "0x83769c":13,
  "0xff77a8":14,
  "0xffccaa":15,
  "0x291814":128,
  "0x111d35":129,
  "0x422136":130,
  "0x125359":131,
  "0x742f29":132,
  "0x49333b":133,
  "0xa28879":134,
  "0xf3ef7d":135,
  "0xbe1250":136,
  "0xff6c24":137,
  "0xa8e72e":138,
  "0x00b543":139,
  "0x065ab5":140,
  "0x754665":141,
  "0xff6e59":142,
  "0xff9d81":143}

# map rgb colors to label fake hexa codes
rgb_to_label={
  "0x000000":'0',
  "0x1d2b53":'1',
  "0x7e2553":'2',
  "0x008751":'3',
  "0xab5236":'4',
  "0x5f574f":'5',
  "0xc2c3c7":'6',
  "0xfff1e8":'7',
  "0xff004d":'8',
  "0xffa300":'9',
  "0xffec27":'a',
  "0x00e436":'b',
  "0x29adff":'c',
  "0x83769c":'d',
  "0xff77a8":'e',
  "0xffccaa":'f',
  "0x291814":'g',
  "0x111d35":'h',
  "0x422136":'i',
  "0x125359":'j',
  "0x742f29":'k',
  "0x49333b":'l',
  "0xa28879":'m',
  "0xf3ef7d":'n',
  "0xbe1250":'o',
  "0xff6c24":'p',
  "0xa8e72e":'q',
  "0x00b543":'r',
  "0x065ab5":'s',
  "0x754665":'t',
  "0xff6e59":'u',
  "0xff9d81":'v'}

# returns pico8 standard palette
def std_palette():
  return {rgb:p8 for rgb,p8 in rgb_to_pico8.items() if p8<16}

def std_rgba_palette():
  return {(int(rgb[2:4],16),int(rgb[4:6],16),int(rgb[6:8],16),255):p8 for rgb,p8 in rgb_to_pico8.items() if p8<16}

# compress the given byte string
# raw = True returns an array of bytes (a byte string otherwise)
def compress_byte_str(s,raw=False,more=False):
  b = bytes.fromhex(s)
  min_size = len(b)
  min_off = 8
  min_len = 3
  if more:
    for l in tqdm(range(8), desc="Compression optimization"):
      cc = Codec(b_off = min_off, b_len = l) 
      compressed = cc.toarray(b)
      if len(compressed)<min_size:
        min_size=len(compressed)
        min_len = l      
  
    logging.debug("Best compression parameters: O:{} L:{} - ratio: {}%".format(min_off, min_len, round(100*min_size/len(b),2)))

  # LZSS compressor  
  cc = Codec(b_off = min_off, b_len = min_len) 
  compressed = cc.toarray(b)
  if raw:
    return compressed
  return "".join(map("{:02x}".format, compressed))


# helper class to check or build a new palette
class AutoPalette:  
  # palette: an array of (r,g,b,a) tuples
  def __init__(self, palette=None):
    self.auto = palette is None
    self.palette = palette or []

  def register(self, rgba):
    # invalid color (drop alpha)?
    if "0x{0[0]:02x}{0[1]:02x}{0[2]:02x}".format(rgba) not in rgb_to_pico8:
      raise Exception("Invalid color: {} in image".format(rgba))
    # returns a 0-15 value for image encoding
    if rgba in self.palette: return self.palette.index(rgba)
    # not found and auto-palette
    if self.auto:
      # already full?
      count = len(self.palette)
      if count==16:
        raise Exception("Image uses too many colors (16+). New color: {} not allowed".format(rgba))
      self.palette.append(rgba)
      return count
    raise Exception("Color: {} not in palette".format(rgba))

  # returns a list of hardware colors matching the palette
  # label indicates if color coding should be using 'fake' hexa or standard
  def pal(self, label=False):
    encoding = rgb_to_pico8
    if label:
      encoding = rgb_to_label
    return list(map(encoding.get,map("0x{0[0]:02x}{0[1]:02x}{0[2]:02x}".format,self.palette)))

class TilesExtractor():
  def extract_tiles(self,texture_name, palette):
    # read image bytes
    src = Image.open(texture_name)
    width, height = src.size
    if width>1024 or height>1024:
      raise Exception("Texture: {} invalid size: {}x{} - Texture file size must be less than 1024x1024px".format(width,height))
    img = Image.new('RGBA', (width, height), (0,0,0,0))
    img.paste(src, (0,0,width,height))

    # extract tiles
    pico_gfx = [bytearray(32)]
    pico_map = bytearray()
    for j in range(0,math.floor(height/8)):
      for i in range(0,math.floor(width/8)):
        data = bytearray()
        for y in range(8):
          # read nimbles
          x_data = bytearray()
          for x in range(0,8,2):
            # print("{}/{}".format(i+x,j+y))
            # image is using the pico palette (+transparency)
            low = palette.register(img.getpixel((i*8 + x, j*8 + y)))
            high = palette.register(img.getpixel((i*8 + x + 1, j*8 + y)))
            x_data.insert(0,low|high<<4)
          data += x_data
        # not referenced zone
        tile = 0
        # known tile?
        if data in pico_gfx:
          tile = pico_gfx.index(data)
        else:
          tile = len(pico_gfx)
          pico_gfx.append(data) 
        # sprite 0 cannot be used
        pico_map.append(tile)        

    # map width
    width=width>>3

    max_tiles = 16*4*4
    if len(pico_gfx)>max_tiles:
      raise Exception("Too many unique tiles: {} in tileset: {} (max: {})".format(len(pico_gfx), texture_name, max_tiles))

    logging.info("Tileset: Found {}/{} unique tiles".format(len(pico_gfx),max_tiles))

    return dotdict({'width':width,'map':pico_map,'gfx':pico_gfx})

def pack_levels(pico_path, carts_path, levels_path):
  extract = TilesExtractor()
  autopalette = AutoPalette()
  
  # extract tiles&map
  tiles = extract.extract_tiles(os.path.join(levels_path, "level3_pico.png"), autopalette)
  sprite_data = bytearray()
  for sprite in tiles.gfx: sprite_data += sprite
  s = compress_byte_str(
    pack_variant(len(tiles.gfx)) + 
    "".join(map("{:02x}".format,sprite_data)) + 
    pack_variant(len(tiles.map)) + 
    "".join(map("{:02x}".format,tiles.map)))
  
  autopalette = autopalette.pal()

  cart_code="""\
pico-8 cartridge // http://www.pico-8.com
version 29
__lua__
-- pico-wings
-- @freds72
-- *********************************
-- generated code - do not edit
-- *********************************
-- tile palette
local _palette={{[0]={},{}}}
#include lzs.lua
#include tquad.lua
#include pwings.lua
""".format(
    autopalette[0],
    ",".join(str(c) for c in autopalette[1:]))

  to_cart(s, pico_path, carts_path, "pwings",3,cart_code=cart_code)

def main():
  parser = argparse.ArgumentParser()
  parser.add_argument("--pico-home", required=True, type=str, help="Full path to PICO8 folder")
  parser.add_argument("--carts-path", required=True,type=str, help="Path to carts folder where game is exported")
  parser.add_argument("--levels-path", required=True,type=str, help="Path to levels data")

  args = parser.parse_args()
  logging.basicConfig(level=logging.INFO)
  # do action
  pack_levels(args.pico_home, args.carts_path, args.levels_path)

  logging.info('DONE')

if __name__ == '__main__':
    main()
