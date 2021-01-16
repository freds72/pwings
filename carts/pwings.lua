-- pico-wings game code
-- globals
local _map,_cells,_cells_map,_grid,_map_lru
local _cam,_plyr

function make_player(x,y,z)
	local pitch=0
	local yaw,dyaw=0,0
	local rpm,drpm=0,0

	-- create tiles
	for i=1,8 do
		for j=0,2 do
			mset(i-1,j,i+j*16)
		end
	end

	return {
		pos={x,y,z},
		m=make_m_from_euler(0,0,0),
		update=function(self)
			local dr,dy,dp=0,0,0
			if(btn(4)) dr=1
			if(btn(0)) dy=-1
			if(btn(1)) dy=1
			if(btn(2)) dp=1
			if(btn(3)) dp=-1			
			
			drpm*=0.8
			drpm+=dr/256
			rpm+=drpm

			-- pitch
			pitch*=0.95
			pitch+=dp/256

			-- yaw
			dyaw*=0.8
			dyaw+=dy/1024
			yaw+=dyaw

			local m=make_m_from_euler(pitch,yaw,0)
			self.pos=v_add(self.pos,m_fwd(m),rpm)
			self.m=m
		end,
		draw=function(self)
			-- backup sprite block
			local buf={}
			for i=0x0,64*64-1,4 do
				buf[i]=$i
			end
			memcpy(0x0,0x4300,64*64)
			palt(8,true)
			--sspr(8,0,58,22,40,50)
			local p={
				{x=-29,y=11,w=1},
				{x=29,y=11,w=1},
				{x=29,y=-11,w=1},
				{x=-29,y=-11,w=1}
			}
			local c,s=cos(-16*dyaw),-sin(-16*dyaw)
			for i,v in pairs(p) do
				local x,y=v.x,v.y
				v.x=63.5+x*c-y*s
				v.y=63.5-x*s-y*c
			end

			tquad(
				p,
				{{0,0},{8,0},{8,3},{0,3}})
			palt()
			-- restore spritesheet
			for i,v in pairs(buf) do
				poke4(i,v)
			end

		end
	}
end

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
	_plyr=make_player(64,10,64)

end

function _update()
	_plyr:update()
  _cam:track(_plyr.pos,_plyr.m)
end

function draw_ground()
	poke(0x5f38, 1) -- texture map 2x2
	poke(0x5f39, 1)

	local m=pack(unpack(_cam.m))
	m_inv(m)
	local fwd,up,right=m_fwd(m),m_up(m),m_right(m)
	local x,y,z=unpack(_cam.pos)
	camera(0,-64)
	for i=-64,63 do
		local vu = v_add(fwd, up, -i/128)
		-- vector toward ground?
		if (vu[2]<0) then 
			local vl = v_add(vu,right,-0.5)    -- left ray
			local vr = v_add(vu,right, 0.5)    -- right ray

			-- y=0 intersection
			local kl,kr=-y/vl[2],-y/vr[2]

			local tx,tz=vl[1]*kl+x,vl[3]*kl+z 
			--rectfill(-64,i,64,i,8)
			tline(0,i,127,i, tx,tz, (vr[1]*kr+x-tx)/128,(vr[3]*kr+z-tz)/128)
		end
	end
	camera()
	poke(0x5f38, 0)
	poke(0x5f39, 0)
end

function _draw()
  cls(0)
	palt(0,false)
	
	-- infinite floor
	draw_ground()

	draw_map(_cam)
	_plyr:draw()

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
	return {
		v[1]+scale*dv[1],
		v[2]+scale*dv[2],
		v[3]+scale*dv[3]}
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
function v_cross(a,b)
	local ax,ay,az=a[1],a[2],a[3]
	local bx,by,bz=b[1],b[2],b[3]
	return {ay*bz-az*by,az*bx-ax*bz,ax*by-ay*bx}
end
function v_normz(v)
	local x,y,z=v[1],v[2],v[3]
	local d=x*x+y*y+z*z
	if d>0.001 then
		d=sqrt(d)
		return {x/d,y/d,z/d}
	end
	return v
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
-- returns basis vectors from matrix
function m_right(m)
	return {m[1],m[2],m[3]}
end
function m_up(m)
	return {m[5],m[6],m[7]}
end
function m_fwd(m)
	return {m[9],m[10],m[11]}
end
-- optimized 4x4 matrix mulitply
function m_x_m(a,b)
	local a11,a21,a31,_,a12,a22,a32,_,a13,a23,a33,_,a14,a24,a34=unpack(a)
	local b11,b21,b31,_,b12,b22,b32,_,b13,b23,b33,_,b14,b24,b34=unpack(b)

	return {
			a11*b11+a12*b21+a13*b31,a21*b11+a22*b21+a23*b31,a31*b11+a32*b21+a33*b31,0,
			a11*b12+a12*b22+a13*b32,a21*b12+a22*b22+a23*b32,a31*b12+a32*b22+a33*b32,0,
			a11*b13+a12*b23+a13*b33,a21*b13+a22*b23+a23*b33,a31*b13+a32*b23+a33*b33,0,
			a11*b14+a12*b24+a13*b34+a14,a21*b14+a22*b24+a23*b34+a24,a31*b14+a32*b24+a33*b34+a34,1
		}
end
function make_m_from_v_angle(up,angle)
	local fwd={-sin(angle),0,cos(angle)}
	local right=v_normz(v_cross(up,fwd))
	fwd=v_cross(right,up)
	return {
		right[1],right[2],right[3],0,
		up[1],up[2],up[3],0,
		fwd[1],fwd[2],fwd[3],0,
		0,0,0,1
	}
end

function make_cam()
  local up={0,1,0}
	return {
		pos={0,0,0},
    track=function(self,pos,m)
      -- inverse view matrix
      pos=v_add(v_add(pos,m_fwd(m),-10),m_up(m),0)
      m[2],m[5]=m[5],m[2]
			m[3],m[9]=m[9],m[3]
      m[7],m[10]=m[10],m[7]
      self.m=m_x_m(m,{
        1,0,0,0,
        0,1,0,0,
        0,0,1,0,
        -pos[1],-pos[2],-pos[3],1
      })
      self.pos=pos
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
  local m=_cam.m
	-- project all potential tiles
	for i,g in pairs(_grid) do
		-- to cam space
    local x,y,z,outcode=((i%5)<<5),0,(i\5<<5),0   
    x,y,z=m[1]*x+m[5]*y+m[9]*z+m[13],m[2]*x+m[6]*y+m[10]*z+m[14],m[3]*x+m[7]*y+m[11]*z+m[15]
    
    if z<1 then outcode=2
		elseif z>128 then outcode=1 end
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
    g.clipcode=outcode&2
	end
	
	-- collect visible cells
	local viz={}
	for k,cell in pairs(_cells) do
    -- visible or partially visible?
		if (cell[1].outcode&
       cell[2].outcode&
       cell[3].outcode&
       cell[4].outcode)==0 then
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
      if cell[1].clipcode+
        cell[2].clipcode+
        cell[3].clipcode+
        cell[4].clipcode>0 then
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
    if cell[1].clipcode+
      cell[2].clipcode+
      cell[3].clipcode+
      cell[4].clipcode>0 then
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