setlocal
set PATH=%PATH%;"c:\Program Files\ImageMagick-7.0.10-Q16"
magick %1 +dither -remap palette.png out.png
