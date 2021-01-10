-- pico-wings game code
-- globals
local _map,_cells,_cells_map,_grid,_map_lru

function _init()
  -- init maps
	-- collision map
  _map,_cells,_cells_map,_grid,_map_lru,_npc_map={},{},{},{},{},{}

	-- 
	local grid_w=4
	-- grid_w intervals = grid_w+1^2 points
	for i=0,(grid_w+1)*(grid_w+1)-1 do
		_grid[i]={x=0,y=0,outcode=0}
	end
	-- direct link to grid vertices?
	for i=0,grid_w*grid_w-1 do
		-- cell coords in grid space 
		-- +1: account for 'additional' ^2+1 point
		local ci=(i%grid_w)+(grid_w+1)*flr(i/grid_w)
		local tiles={
			_grid[ci],
			_grid[ci+1],
			_grid[ci+grid_w+2],
			_grid[ci+grid_w+1]
		}
		_cells[i]=tiles
    _cells_map[i]={}

  end
  --
  decompress(unpack_map,_map)
end

local _x,_y=0,0
function _update()
  local dx,dy=0,0
  if(btn(0)) dx=-1
  if(btn(1)) dx=1
  if(btn(2)) dy=-1
  if(btn(3)) dy=1
  _x+=dx/8
  _y+=dy/8
end

function _draw()
  cls()
  if btn(4) then
    spr(0,0,0,16,16)
  else
    draw_map(_x,_y,8,0)
  end
  pal(_palette,1)
end

-->8
-- map & draw helpers

-- check for the given tile flag
function fmget(x,y)
	return fget(_map[(x\1)|(y\1)<<7])
end

function map_set(i,j,s)
	_map[i|j<<7]=s
	-- cell coord (128x128)->(4x4)
	local ck=i\32+(j\32<<2)
	local cell_map=_cells_map[ck]
	-- cell is 4*dword with a stride of 128/4 = 32
	-- cell entry is packed as a dword
	local k=(band(i,31)\4<<2)+(band(j,31)<<7)
	-- shift 
	local shift=(i%4)<<3
  cell_map[k]=(cell_map[k] or 0)&rotl(0xffff.ff00,shift) | (0x0.0001<<shift)*s
  for _,entry in pairs(_map_lru) do
		if(entry.k==ck) entry.k=-1 entry.t=-1
	end
end

function draw_map(x,y,z,a)
	local ca,sa=cos(a),-sin(a)
	local scale=8/(z+8)
	-- project all potential tiles
	for i,g in pairs(_grid) do
		-- to cam space
		local ix,iy,outcode=((i%5)<<5)-x,(i\5<<5)-y,0
		ix,iy=scale*(ca*ix+sa*iy)+8,scale*(-sa*ix+ca*iy)+14
		if ix>16 then outcode=2
		elseif ix<0 then outcode=1 end
		if iy>16 then outcode|=8
		elseif iy<0 then outcode|=4 end
		-- to screen space
		g.x=ix<<3
		g.y=iy<<3
		g.outcode=outcode
	end
	
	-- collect visible cells
	local viz={}
	for k,cell in pairs(_cells) do
		-- visible or partially visible?
		if(cell[1].outcode&
			 cell[2].outcode&
			 cell[3].outcode&
			 cell[4].outcode)==0 then
			viz[k]=cell
		end
	end
	
	-- draw existing cache entries
	for i,entry in pairs(_map_lru) do
		local cell=viz[entry.k]
		if cell then
			local offset=i<<5
			tquad(cell,{
				offset,0,
				32+offset,0,
				32+offset,32,
				offset,32})
			-- update lru time
			entry.t=time()
			-- done
			viz[entry.k]=nil
		end
	end
   
	-- remaining tiles
	-- (e.g. cache misses)
	for k,cell in pairs(viz) do
		local mint,mini=32000,#_map_lru+1
		-- cache full?
		if mini>3 then
			-- find lru entry
			for i=1,3 do
				local entry=_map_lru[i]
				if entry.t<mint then
					mint,mini=entry.t,i
				end
			end
		end
		-- add/reuse cache entry
		_map_lru[mini]={k=k,t=time()}
		-- fill cache entry
		local mem=0x2000+(mini<<5)
		for base,v in pairs(_cells_map[k]) do
			poke4(mem+base,v)
		end
		-- draw with fresh cache entry		
		local offset=mini<<5
		tquad(cell,{
			offset,0,
			32+offset,0,
			32+offset,32,
			offset,32})
	end  
end

-->8
-- data unpacking functions
-- unpack a fixed 16:16 value
function unpack_fixed()
	return mpeek()<<8|mpeek()|mpeek()>>8|mpeek()>>16
end
function unpack_variant()
	local h=mpeek()
	-- above 127?
	if band(h,0x80)>0 then
		h=bor(shl(band(h,0x7f),8),mpeek())
	end
return h
end
-- unpack an array of bytes
function unpack_array(fn)
  local n=unpack_variant()
	for i=1,n do
		fn(i-1)
	end
end
function unpack_map()
  local buf={}
  unpack_array(function(i)
    -- starting point
    local mem=((i%16)*4)+(i\16)*64*8
    for j=0,7 do
      buf[mem+j*64]=unpack_fixed()
    end
  end)
  -- maps
  unpack_array(function(i)
    map_set(i%128,i\128,mpeek())
  end)

  -- commit sprites
  for i,v in pairs(buf) do
    poke4(i,v)
  end
end