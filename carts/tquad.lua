-- quad rasterization with tline uv coordinates
function tquad(v,uv)
	local p0,spans=v[4],{}
	local x0,y0,u0,v0=p0.x,p0.y,uv[7],uv[8]
	-- ipairs is slower for small arrays
	for i=1,4 do
		local p1=v[i]
		local x1,y1,u1,v1=p1.x,p1.y,uv[(i<<1)-1],uv[i<<1]
		local _x1,_y1,_u1,_v1=x1,y1,u1,v1
		if(y0>y1) x0,y0,x1,y1,u0,v0,u1,v1=x1,y1,x0,y0,u1,v1,u0,v0
		local dy=y1-y0
		local dx,du,dv=(x1-x0)/dy,(u1-u0)/dy,(v1-v0)/dy
		if(y0<0) x0-=y0*dx u0-=y0*du v0-=y0*dv y0=0
		local cy0=ceil(y0)
		-- sub-pix shift
		local sy=cy0-y0
		x0+=sy*dx
		u0+=sy*du
		v0+=sy*dv
		for y=cy0,min(ceil(y1)-1,127) do
			local span=spans[y]
			if span then
				--rectfill(x[1],y,x0,y,offset/16)
				
				local a,au,av,b,bu,bv=span.x,span.u,span.v,x0,u0,v0
				if(a>b) a,au,av,b,bu,bv=b,bu,bv,a,au,av
				local dab=b-a
				local dau,dav=(bu-au)/dab,(bv-av)/dab
				local ca,cb=ceil(a),ceil(b)-1
				if ca<=cb then
					-- sub-pix shift
					local sa=ca-a
					tline(ca,y,cb,y,au+sa*dau,av+sa*dav,dau,dav)
				end
			else
				spans[y]={x=x0,u=u0,v=v0}
			end
			x0+=dx
			u0+=du
			v0+=dv
		end
		x0,y0,u0,v0=_x1,_y1,_u1,_v1
	end

	--[[
	local v0,v1,v2,v3=
		v[1],
		v[2],
		v[3],
		v[4]
	line(v0.x,v0.y,v1.x,v1.y,7)
	line(v1.x,v1.y,v2.x,v2.y,7)
	line(v2.x,v2.y,v3.x,v3.y,7)
	line(v3.x,v3.y,v0.x,v0.y,7)
	]]
end