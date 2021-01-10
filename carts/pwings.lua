-- pico-wings game code
-- globals
local _map,_cells,_cells_map,_grid,_map_lru
local _cam

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

  _cam=make_cam()
end

local _x,_y=64,64
function _update()
  local dx,dy=0,0
  if(btn(0)) dx=-1
  if(btn(1)) dx=1
  if(btn(2)) dy=-1
  if(btn(3)) dy=1
  _x+=dx/8
  _y+=dy/8

  _cam:track({_x,5,_y},make_m_from_euler(0.08,time()/32,0))
end

function _draw()
  cls(1)
  palt(0,false)
  if btn(4) then
    spr(0,0,0,16,16)
  else
    draw_map(_cam)
  end
  pal(_palette,1)
end

-->8
-- maths & cam
function lerp(a,b,t)
	return a*(1-t)+b*t
end

function make_v(a,b)
	return {
		b[1]-a[1],
		b[2]-a[2],
		b[3]-a[3]}
end
function v_clone(v)
	return {v[1],v[2],v[3]}
end
function v_dot(a,b)
	return a[1]*b[1]+a[2]*b[2]+a[3]*b[3]
end
function v_scale(v,scale)
	v[1]*=scale
	v[2]*=scale
	v[3]*=scale
end
function v_add(v,dv,scale)
	scale=scale or 1
	v[1]+=scale*dv[1]
	v[2]+=scale*dv[2]
	v[3]+=scale*dv[3]
end
function v_lerp(a,b,t)
	return {
		lerp(a[1],b[1],t),
		lerp(a[2],b[2],t),
		lerp(a[3],b[3],t)
	}
end
function v2_lerp(a,b,t)
	return {
		lerp(a[1],b[1],t),
		lerp(a[2],b[2],t)
	}
end

-- matrix functions
function m_x_v(m,v)
	local x,y,z=v[1],v[2],v[3]
	v[1],v[2],v[3]=m[1]*x+m[5]*y+m[9]*z+m[13],m[2]*x+m[6]*y+m[10]*z+m[14],m[3]*x+m[7]*y+m[11]*z+m[15]
end

function make_m_from_euler(x,y,z)
		local a,b = cos(x),-sin(x)
		local c,d = cos(y),-sin(y)
		local e,f = cos(z),-sin(z)
  
    -- yxz order
  local ce,cf,de,df=c*e,c*f,d*e,d*f
	 return {
	  ce+df*b,a*f,cf*b-de,0,
	  de*b-cf,a*e,df+ce*b,0,
	  a*d,-b,a*c,0,
	  0,0,0,1}
end

-- only invert 3x3 part
function m_inv(m)
	m[2],m[5]=m[5],m[2]
	m[3],m[9]=m[9],m[3]
	m[7],m[10]=m[10],m[7]
end

function make_cam()
	return {
		pos={0,0,0},
		track=function(self,pos,m)
    self.pos=v_clone(pos)

		-- inverse view matrix
    self.m=m
    m_inv(self.m)
	 end
  }
end

function z_poly_clip(znear,v,uv)
	local res,res_uv,v0,uv0={},{},v[#v],uv[#v]
	local d0=v0[3]-znear
	for i=1,#v do
		local v1,uv1=v[i],uv[i]
		local d1=v1[3]-znear
		if d1>0 then
      if d0<=0 then
        local t=d0/(d0-d1)
        local nv=v_lerp(v0,v1,t) 
        local w=128/nv[3]
        res[#res+1]={x=63.5+nv[1]*w,y=63.5-nv[2]*w,w=w}
        res_uv[#res_uv+1]=v2_lerp(uv0,uv1,t)
			end
      res[#res+1]=v1
      res_uv[#res_uv+1]=uv1
		elseif d0>0 then
      local t=d0/(d0-d1)
			local nv=v_lerp(v0,v1,t)
      local w=128/nv[3]
      res[#res+1]={x=63.5+nv[1]*w,y=63.5-nv[2]*w,w=w}
      res_uv[#res_uv+1]=v2_lerp(uv0,uv1,t)
		end
    v0=v1
    uv0=uv1
		d0=d1
	end
	return res,res_uv
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

function draw_map(cam)
  local ca,sa=cos(a),-sin(a)
  local m,cx,cy,cz=_cam.m,unpack(_cam.pos)
	-- project all potential tiles
	for i,g in pairs(_grid) do
		-- to cam space
    local x,y,z,outcode=((i%5)<<5)-cx,-cy,(i\5<<5)-cz,0    
    x,y,z=m[1]*x+m[5]*y+m[9]*z+m[13],m[2]*x+m[6]*y+m[10]*z+m[14],m[3]*x+m[7]*y+m[11]*z+m[15]
    
    if z<0 then outcode=2
		elseif z>96 then outcode=1 end
    if 2*x>z then outcode|=4
		elseif 2*x<-z then outcode|=8 end
		if 2*y>z then outcode|=16
    elseif 2*y<-z then outcode|=32 end
    -- save world space coords for clipping
    g[1]=x
    g[2]=y
    g[3]=z
    -- to screen space
    local w=128/z
		g.x=63.5+x*w
    g.y=63.5-y*w
    g.w=w
    g.outcode=outcode
    g.clipcode=outcode&1
	end
	
	-- collect visible cells
	local viz={}
	for k,cell in pairs(_cells) do
    -- visible or partially visible?
		if cell[1].outcode&
       cell[2].outcode&
       cell[3].outcode&
       cell[4].outcode==0 then
      viz[k]=cell
		end
	end
	
  -- draw existing cache entries
  local tq=0
	for i,entry in pairs(_map_lru) do
		local cell=viz[entry.k]
		if cell then
      local offset=i<<5
      local v,uv=cell,{
				{offset,0},
				{32+offset,0},
				{32+offset,32},
        {offset,32}}
      if cell[1].outcode+
        cell[2].outcode+
        cell[3].outcode+
        cell[4].outcode!=0 then
        v,uv=z_poly_clip(1,v,uv)
      end
			tquad(v,uv)
      tq+=1
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
		local mem=0x2000|mini<<5
		for base,v in pairs(_cells_map[k]) do
			poke4(mem+base,v)
		end
		-- draw with fresh cache entry		
    local offset=mini<<5
    tq+=1
    local v,uv=cell,{
      {offset,0},
      {32+offset,0},
      {32+offset,32},
      {offset,32}}
    if cell[1].outcode+
      cell[2].outcode+
      cell[3].outcode+
      cell[4].outcode!=0 then
      v,uv=z_poly_clip(1,v,uv)
    end    
		tquad(v,uv)
  end  
  print(tq,2,2,7)
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