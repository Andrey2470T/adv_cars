adv_vehicles = {}
global_nodenames_list = {}

local i = 0
for node_name, def in pairs(minetest.registered_nodes) do
	i = i+1
	global_nodenames_list[i] = node_name
end

-- Rounds 'num' to the tenth and return the rounded number.
local function round_num(num)
	local int, frac = math.modf(num)
	local to_str = tostring(num)
	local to_str_frac = tostring(frac)
	local dot_ind = string.find(to_str_frac, '.')
	local tenth_rank = string.sub(to_str_frac, dot_ind+2, dot_ind+2)
	local new_frac = string.gsub(to_str_frac, tenth_rank, "0")
	local new_frac_to_int = tonumber(new_frac)
	local new_frac2 = string.gsub(to_str, tenth_rank, tostring(tonumber(tenth_rank)+1))
	local rounded_num = (new_frac_to_int < 0.05 and num-new_frac) or (new_frac_to_int >= 0.05 and tonumber(string.sub(new_frac2, 1, dot_ind+2)))
	return rounded_num
end

-- The method calculates new position for any car seat (for example, after a car turning)
adv_vehicles.rotate_point_around_other_point = function (circle_centre_pos, rotating_point_pos, fixed_point_yaw, current_point_yaw)
	local turn_angle = current_point_yaw
	if fixed_point_yaw > current_point_yaw then
		turn_angle = fixed_point_yaw+current_point_yaw
	elseif fixed_point_yaw < current_point_yaw then
		turn_angle = -(fixed_point_yaw+current_point_yaw)
	end
	local new_pos = {x=rotating_point_pos.x, y=circle_centre_pos.y, z=rotating_point_pos.z}
	new_pos.x = circle_centre_pos.x + (rotating_point_pos.x-circle_centre_pos.x) * math.cos(turn_angle) - (rotating_point_pos.z-circle_centre_pos.z) * math.sin(turn_angle)
	new_pos.z = circle_centre_pos.z + (rotating_point_pos.z-circle_centre_pos.z) * math.cos(turn_angle) + (rotating_point_pos.x-circle_centre_pos.x) * math.sin(turn_angle)
	return new_pos
end

-- The method attaches a player to the car
adv_vehicles.attach_player_to_car = function(player, car, seated, model, animation)
    if car.seats_list[seated].busy_by then
	    minetest.chat_send_player(player:get_player_name(), "This seat is busy by" .. car.seats_list[seat_num].busy_by .. "!")
	    return 
    end
    
    car.seats_list[seated].busy_by = player:get_player_name()
    local car_rot = car.object:get_rotation()
    local fixed_car_yaw = car.fixed_car_rotate_angle
    local new_seat_pos = adv_vehicles.rotate_point_around_other_point({x=0, y=0, z=0}, car.seats_list[seated].pos, fixed_car_yaw, math.deg(car_rot.y))
    new_seat_pos.y = 9
    car.seats_list[seated].pos = new_seat_pos
    local meta = player:get_meta()
    meta:set_string("is_sit", minetest.serialize({car_name, seated}))
    local new_player_rot = {x=math.deg(car_rot.x), y=car_rot.y-180, z=math.deg(car_rot.z)}
    player:set_attach(car.object, "", new_seat_pos, new_player_rot)
    local eye_offset = player:get_eye_offset()
    player:set_eye_offset({x=-4.0, y=-3.0, z=3.0}, eye_offset)
    
    
    if model then
	    player:set_properties({mesh=model})
    end
    if animation then
	    player:set_animation({x=animation.x, y=animation.y})
    end
end

-- The method detaches a player from the car
adv_vehicles.detach_player_from_car = function (player, car, seated, model, animation)
	if not car.seats_list[seated].busy_by then
		return
	end
	
	car.fixed_car_rotate_angle = math.deg(car.object:get_yaw())
	local meta = player:get_meta()
	meta:set_string("is_sit", "")
	car.seats_list[seated].busy_by = nil
	player:set_detach()
	player:set_eye_offset({x=0, y=0, z=0}, {x=0, y=0, z=0})
	if model then
		player:set_properties({mesh=model})
	end
	if animation then
		player:set_animation({x=animation.x, y=animation.y})
	end
end

adv_vehicles.pave_vector = function (car, vect_length, old_yaw)
	local yaw = car.object:get_yaw()
	local pos2 = {x=0, y=0, z=vect_length}
	
	local pos3 = adv_vehicles.rotate_point_around_other_point({x=0, y=0, z=0}, pos2, old_yaw, yaw)
	local vect = vector.new({x=0, y=0, z=0})
	local vector_coords = vector.direction(vect, pos3) 
	return vector_coords, yaw
end

adv_vehicles.rotate_collisionbox = function (car, yaw) 
	if yaw % 90 ~= 0 then
		return
	end
	local car_cbox = car.object:get_properties().collisionbox
	local cur_cbox_dir = car.collisionbox_yaw.along_axis
	local axle_num 
	local new_axle_num = 1
	local axises_table = {"z", "x", "-z", "-x"}
	for num, axis in pairs(axises_table) do
		if axis == cur_cbox_dir then
			axle_num = num
			break
		end
	end
	local times = yaw / 90
	for i = 1, math.abs(times)+1 do
		if times < 0 then
			if axises_table[1] == cur_cbox_dir then
				new_axle_num = axises_table[#axises_table]
			else
				new_axle_num = new_axle_num - 1
			end
		else
			if axises_table[#axises_table] == cur_cbox_dir then
				new_axle_num = axises_table[1]
			else
				new_axle_num = new_axle_num + 1
			end
		end
	end
	
	local new_cbox_dir = axises_table[new_axle_num]
	local cboxes = {
		["z"] = {car_cbox[1], car_cbox[2], car_cbox[3], car_cbox[4], car_cbox[5], car_cbox[6]},
		["x"] = {car_cbox[3], car_cbox[2], car_cbox[1], car_cbox[6], car_cbox[5], car_cbox[4]},
		["-z"] = {car_cbox[1]*-1, car_cbox[2], car_cbox[3]*-1, car_cbox[4]*-1, car_cbox[5], car_cbox[6]*-1},
		["-x"] = {car_cbox[3]*-1, car_cbox[2], car_cbox[1]*-1, car_cbox[6]*-1, car_cbox[5], car_cbox[4]*-1}
	}
	local new_cbox = cboxes[new_cbox_dir]
	car.object:set_properties({collisionbox=new_cbox})
	local old_cbox_yaw = car.collisionbox_yaw.val
	car.collisionbox_yaw = {val=old_cbox_yaw+yaw, along_axis=new_cbox_dir}
end
	--[[while temp_degs ~= 0 do
		temp_degs = temp_degs - 90
		if yaw < 0 then
			if axises_table[1] == cur_cbox_dir then
				axle = axises_table[#axises_table]
			else
				axle = 
		else
			times = times + 1
		end
	end
	
	for num, axis in pairs(axises_table) do
		
	local cboxes = {
		["z"] = {car_cbox[1], car_cbox[2], car_cbox[3], car_cbox[4], car_cbox[5], car_cbox[6]},
		["x"] = {car_cbox[3], car_cbox[2], car_cbox[1], car_cbox[6], car_cbox[5], car_cbox[4]},
		["-z"] = {car_cbox[1]*-1, car_cbox[2], car_cbox[3]*-1, car_cbox[4]*-1, car_cbox[5], car_cbox[6]*-1},
		["-x"] = {car_cbox[3]*-1, car_cbox[2], car_cbox[1]*-1, car_cbox[6]*-1, car_cbox[5], car_cbox[4]*-1}
	}
	for num, axis in pairs(axises_table) do
		if axis == cbox_dir then
			
	for degs, cbox in pairs(cboxes) do
		if tostring(yaw) == degs then
			car.object:set_properties({collisionbox=cbox})
			return true
		end
	end
end]]
		
		
--[[adv_cars.falldown_car = function (car)
	local name = car.entity_name
	local car_cbox_n_x = minetest.registered_entities[name].collisionbox[1]
	local car_cbox_n_y = minetest.registered_entities[name].collisionbox[2]
	local car_cbox_n_z = minetest.registered_entities[name].collisionbox[3]
	local car_cbox_p_x = minetest.registered_entities[name].collisionbox[4]
	local car_cbox_p_z = minetest.registered_entities[name].collisionbox[6]
	local car_pos = car.object:get_pos()
	local pos_cbox_n_x = car_pos.x - car_cbox_n_x
	local pos_cbox_n_z = car_pos.z - car_cbox_n_z
	local pos_cbox_p_x = car_pos.x - car_cbox_p_x
	local pos_cbox_p_z = car_pos.z - car_cbox_p_z
 	local pos_cbox_n_y = car_pos.y - math.abs(car_cbox_n_y)
	
	local node1 = minetest.get_node({x=pos_cbox_n_x, y=pos_cbox_n_y-15, z=pos_cbox_n_z})
	local node2 = minetest.get_node({x=pos_cbox_p_x, y=pos_cbox_n_y-15, z=pos_cbox_n_z})
	local node3 = minetest.get_node({x=pos_cbox_n_x, y=pos_cbox_n_y-15, z=pos_cbox_p_z})
	local node4 = minetest.get_node({x=pos_cbox_p_x, y=pos_cbox_n_y-15, z=pos_cbox_p_z})
	local node1 = minetest.get_node(node1_pos)
	local node2 = minetest.get_node(node2_pos)
	local node3 = minetest.get_node(node3_pos)
	local node4 = minetest.get_node(node4_pos)
	local node1_name = node.name
	local node_cboxes = minetest.registered_nodes[node_name].collisionbox.fixed or minetest.registered_nodes[node_name].node_box.fixed
	local max_cbox_top = 0
	for _, node_cbox in ipairs(node_cboxes) do
		local node_cbox_top = node_pos.y+node_cbox.y
		if node_cbox_top > max_cbox_top then
			max_cbox_top = node_cbox_top
		end
	end
		
	
	local pos = car.object:get_pos()
	local acc = car.object:get_acceleration()
	if acc.y == 0 and not self.collide_y then
		car.object:set_acceleration({x=acc.x, y=-0.1, z=acc.z})
		self.y = pos.y
	elseif acc.y ~= 0 and pos.y ~= self.y then
		car.object:set_acceleration({x=acc.x, y=acc.y*4, z=acc.z})
		self.y = pos.y
	elseif acc.y ~= 0 and pos.y == self.y then
		self.collide_y = true
		car.object:set_acceleration({x=acc.x, y=0, z=acc.z})
	end
	
	if node.name == "air" and pos.cbox_bottom > max_cbox_top then  -- UNTESTED
		if acc.y == 0 then
			car.object:set_acceleration({x=acc.x, y=-0.1, z=acc.z})
			return true
		end
		car.object:set_acceleration({x=acc.x, y=acc.y*4, z=acc.z})
	else
		car.object:set_acceleration({x=acc.x, y=0, z=acc.z})
	end
end]]

local is_acc_set
local is_oppos_acc_set
local is_fallen
-- Bounces a car only due to the falling.
adv_vehicles.collide = function (car)
	local vel = car.object:get_velocity()
	local fixed_vel = car.car_vel
	local seats_list = car.seats_list
	local hp = car.object:get_hp()
	if vel.y == 0 and fixed_vel ~= 0 then
		if not is_fallen then
		is_fallen = true
		local acc = car.object:get_acceleration()
		car.object:set_acceleration({x=acc.x, y=fixed_vel*-5, z=acc.z})
		car.object:set_hp(hp-math.abs(math.ceil(fixed_vel)), {type="fall"})
		for seated, data in pairs(seats_list) do
			if seated.busy_by then
			     local player = minetest.get_player_by_name(seated.busy_by)
			     local player_hp = player:get_hp()
			     player:set_hp(player_hp-math.abs(math.ceil(fixed_vel)), {type="fall"})
			end
		end
		end
	else
		is_fallen = nil
	end
end

adv_vehicles.car_handle = function (player, car, controls, yaw, max_vel)
	if controls.right then
		car.object:set_yaw(yaw-math.rad(1))
		local new_yaw = math.deg(car.object:get_yaw())
		local fixed_cbox_yaw = car.collisionbox_yaw.val
		if new_yaw-fixed_cbox_yaw <= -90 then
			minetest.debug("1")
		      adv_vehicles.rotate_collisionbox(car, -90)
		end
	end
	if controls.left then
		car.object:set_yaw(yaw+math.rad(1))
		local new_yaw = math.deg(car.object:get_yaw())
		local fixed_cbox_yaw = car.collisionbox_yaw.val
		if new_yaw+fixed_cbox_yaw >= 90 then
			minetest.debug("2")
		      adv_vehicles.rotate_collisionbox(car, 90)
		end
	end
	if not new_yaw then
		car.object:get_yaw()
	end
	
	local vector_coords, new_yaw = adv_vehicles.pave_vector(car, -1.2, yaw)
	local step_acc = vector.length(vector_coords)
	local acc = car.object:get_acceleration()
	local vel = car.object:get_velocity()
	if (math.abs(vel.x) or math.abs(vel.z)) >= max_vel then
		vector_coords.x = 0
		vector_coords.z = 0
	end
	
	if controls.up then
		car.object:set_acceleration({x=vector_coords.x/step_acc, y=acc.y, z=vector_coords.z/step_acc})
		is_acc_set = true
		
	else
		local vel = car.object:get_velocity()
		if (vel.x and vel.z) ~= 0 then
			if is_acc_set then
			     car.object:set_acceleration({x=acc.x*-1, y=acc.y, z=acc.z*-1})
			     is_acc_set = nil
			end
		        if ((math.abs(vel.x) and math.abs(vel.z)) < 0.05) and ((vel.x and vel.z) > 0) then
			    car.object:set_acceleration({x=0, y=acc.y, z=0})
			    car.object:set_velocity({x=0, y=vel.y, z=0})
			end
		end
	end
	
	if controls.down then
		car.object:set_acceleration({x=(vector_coords.x/step_acc)*-1, y=acc.y, z=(vector_coords.z/step_acc)*-1})
		is_oppos_acc_set = true
		
	else
		local vel = car.object:get_velocity()
		if (vel.x and vel.z) ~= 0 then
			if is_oppos_acc_set then
				car.object:set_acceleration({x=acc.x, y=acc.y, z=acc.z})
				is_oppos_acc_set = nil
			end
			if ((math.abs(vel.x) and math.abs(vel.z)) > 0.05) and ((vel.x and vel.z) < 0) then
				car.object:set_acceleration({x=0, y=acc.y, z=0})
				car.object:set_velocity({x=0, y=vel.y, z=0})
			end
		end
	end	
	return new_yaw
		
	--[[minetest.register_globalstep(function (dtime)
		local entity = car.object:get_luaentity()
		local meta = minetest.deserialize(player:get_meta():get_string("is_sit"))
		if entity and meta ~= (nil and "") then
		    local vel = entity.object:get_velocity()
		    time = dtime + time
		    minetest.debug(round_num(time))
		    if (vel.x and vel.y and vel.z) == 0 then
			   car.object:set_velocity(vector_coords)
			   car.object:set_acceleration({x=vector_coords.x / step_acc, y=0, z=vector_coords.z / step_acc})
			   local acc = car.object:get_acceleration()
         		   car.object:set_velocity({x=vector_coords.x+acc.x, y=vector_coords.y, z=vector_coords.z+acc.z})
		    
		    elseif (vel.x and vel.y and vel.z) > 0 and round_num(time) >= 1.2 then
			   minetest.debug("RRRRRRRRR")
				local acc = entity.object:get_acceleration()
			   car.object:set_acceleration({x=acc.x * step_decel, y=0, z=acc.z * step_decel})
			   local acc = car.object:get_acceleration()
			   local vel2 = car.object:get_velocity()
			   car.object:set_velocity({x=vel2.x-acc.x, y=vel2.y, z=vel2.z-acc.z})
			   step_decel = step_decel - 0.05
		    end
		end
	end)]]
end
	                            
		
--[[adv_cars.nearby_nodes_are = function (car)
	local vel = car.object:get_velocity()
	local pos = car.object:get_pos()
	local meta = minetest.deserialize(minetest.get_meta():get_string("is_sit"))
	local z_face = minetest.registered_entities[meta.car_name].collisionbox[6]
	if (vel.x and vel.y and vel.z) ~= 0 then
		
		local nearby_nodes = minetest.find_node_near(pos, z_face, global_nodenames_list)]]

adv_vehicles.register_car = function (carname, car_properties)
	minetest.register_entity("adv_vehicles:"..carname, {
		visual = "mesh",
		physical = true,
		mass = car_properties.mass or 2000,
		max_vel = car_properties.max_vel or 120,
		collide_with_objects = true,
		collisionbox = car_properties.cbox,
		mesh = car_properties.model,
		textures = car_properties.textures,
		visual_size = car_properties.visual_size or {x=1, y=1, z=1},
		use_texture_alpha = true,
		on_activate = function (self, staticdata, dtime_s)
			self.fixed_car_rotate_angle = 0
			self.collisionbox_yaw = {val=0, along_axis="z"}
			self.entity_name = "adv_vehicles:"..carname
			self.seats_list = car_properties.seats
			self.car_vel = 0
			local x_offset = car_properties.player_eye_offset.x
			local z_offset = car_properties.player_eye_offset.z
			for seated, data in pairs(self.seats_list) do
				self.seats_list[seated].pos = {x=x_offset, y=0, z=z_offset}
				x_offset = x_offset * -1
			end
	                                               
			local acc = self.object:get_acceleration()
			local gravity_strength = car_properties.mass * -100
			self.object:set_acceleration({x=acc.x, y=gravity_strength, z=acc.z})
			self.fixed_car_rotate_angle = self.object:get_yaw()
			minetest.register_globalstep(function(dtime)
				local entity = self.object:get_luaentity()
				if entity then
				local vel = self.object:get_velocity()
				if vel.y ~= 0 then
				    self.car_vel = vel.y
				end
				local acc = self.object:get_acceleration()
				if acc.y > 0 then
				self.object:set_acceleration({x=acc.x, y=gravity_strength, z=acc.z})
				end
				adv_vehicles.collide(self)
				end
			end)
		end,
		on_handle = adv_vehicles.car_handle,
		on_death = function (self, killer)
			for num, data in pairs(self.seats_list) do
				if self.seats_list[num].busy_by and minetest.get_player_by_name(self.seats_list[num].busy_by) then adv_vehicles.detach_player_from_car(killer, self, num, "character.b3d") end
		        end
		end,
		on_attach_child = function (self, child)
			local yaw = self.object:get_yaw()
			local meta = minetest.deserialize(child:get_meta():get_string("is_sit"))
			if meta.passenger then return end
			minetest.register_globalstep(function(dtime)
				local entity = self.object:get_luaentity()
				if entity then
					if self.seats_list.driver.busy_by then
						local new_yaw = self.on_handle(child, entity, child:get_player_control(), yaw, car_properties.max_vel)
						yaw = new_yaw
					end
	                                                                           
				end
			end)
		end,  -- WRITE !!!
		on_rightclick = function (self, clicker)
			local seats_list = self.seats_list
			for seated, data in pairs(seats_list) do
				if data.busy_by == nil  then
					if seated == "driver" then adv_vehicles.attach_player_to_car(clicker, self, seated, "driver.b3d")
					else adv_vehicles.attach_player_to_car(clicker, self, seated, nil, {x=81, y=81}) end
					break
				elseif data.busy_by == clicker:get_player_name() then
					if seated == "driver" then adv_vehicles.detach_player_from_car(clicker, self, seated, "character.b3d")
					else adv_vehicles.detach_player_from_car(clicker, self, seated, nil, {x=1, y=80}) end
					break
				end
			end
		end
	})
end
local died_cars = {}
--[[minetest.register_entity("adv_vehicles:simple_car", {
	visual = "mesh",
	physical = true,
	collide_with_objects = true,
	collisionbox = {-1.2, -0.5, -3.0, 1.2, 1.5, 3.0},
	mesh = "simple_car.b3d",
	textures = {"simple_car.png"},
	use_texture_alpha = true,
	on_activate = function (self, staticdata, dtime_s)
		local n_x_offset = -4.0
		local n_z_offset = -4.0
		self.fixed_car_rotate_angle = 0
		self.collisionbox_yaw = {val=0, along_axis="z"}
		self.entity_name = "adv_cars:simple_car"
		self.seats_list = {["driver"]={busy_by=nil}, ["passenger"]={busy_by=nil}}
		
		-- Calculates initial positions for each car seat after spawning the car
		for seated, data in pairs(self.seats_list) do
			self.seats_list[seated].pos = {x=n_x_offset, y=0, z=n_z_offset}
			n_x_offset = n_x_offset * -1
			
		end
		
                local acc = self.object:get_acceleration()                                
		self.object:set_acceleration({x=acc.x, y=-7.0, z=acc.z})
		self.fixed_car_rotate_angle = self.object:get_yaw()
		--[[if not time then
			time = 0
		end
	        if not time_exp then
			time_exp = 0
		end
		minetest.register_globalstep(function (dtime)
			local object = self.object:get_luaentity()
			if object then
			    time = dtime + time
			    minetest.debug(math.floor(time))
			    if math.floor(time) - time_exp == 1 then
				   self.after_instant(object)
				   time_exp = time_exp + 1
			    end
			end
		end)
			
	end,
	on_handle = adv_cars.car_handle,
	--[[on_step = function(self, dtime)
		if not time then
			time = 0
		end
		
		minetest.debug(dtime)
		if math.floor(dtime) - time == 0.5 then 
			minetest.debug("TRUE")
		        adv_cars.falldown_car(self)
			time = time + 0.5
		end
	end,
	on_death = function (self, killer)
		for num, data in pairs(self.seats_list) do
			if self.seats_list[num].busy_by and minetest.get_player_by_name(self.seats_list[num].busy_by) then
				adv_cars.detach_player_from_car(killer, self, num, "character.b3d")
			end
		end
	end,
	on_attach_child = function (self, child)
		local yaw = self.object:get_yaw()
		local meta = minetest.deserialize(child:get_meta():get_string("is_sit"))
		if meta.passenger then
			return
		end
		minetest.register_globalstep(function(dtime)
			local entity = self.object:get_luaentity()
			if entity then
				if self.seats_list.driver.busy_by then
			                 local new_yaw = self.on_handle(child, entity, child:get_player_control(), yaw)
			                 yaw = new_yaw
				end
			    
			end
		end)
	end,
	on_rightclick = function (self, clicker)
		local seats_list = self.seats_list
		for seated, data in pairs(seats_list) do
			if data.busy_by == nil  then
				if seated == "driver" then adv_cars.attach_player_to_car(clicker, self, seated, "driver.b3d")
				else adv_cars.attach_player_to_car(clicker, self, seated, nil, {x=81, y=81}) end
				break
			elseif data.busy_by == clicker:get_player_name() then
				if seated == "driver" then adv_cars.detach_player_from_car(clicker, self, seated, "character.b3d")
				else adv_cars.detach_player_from_car(clicker, self, seated, nil, {x=1, y=80}) end
				break
			end
		end
	end
})

--[[minetest.register_on_joinplayer(function (player)
	local meta = player:get_meta()
	local attach = player:get_attach()
	if attach then
		local parent = attach[1]
		local entity = parent:get_luaentity()
		if entity then
		     local seat_num = meta:get_string("is_sit").seat_num
		     entity.seats_list[seat_num] = nil
		     adv_cars.attach_player_to_car(player, parent, seat_num, "driver.b3d")
		end
	end
end)]]
	
minetest.register_on_dieplayer(function (player)
	local meta = player:get_meta()
	if meta:get_string("is_sit") ~= (nil or "") then
		local attach = player:get_attach()
		local player_meta = minetest.deserialize(meta:get_string("is_sit"))
		local seated = player_meta.seated
		adv_vehicles.detach_player_from_car(player, attach[1], seated, "character.b3d")
        end
end)

                                                  
    
