shader_type spatial;

render_mode unshaded, depth_draw_always, fog_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

uniform vec3 local_rotation_axis = vec3(0, 1, 0);

uniform float rotation_speed = 0;

uniform int sample_count = 8;

uniform float shape_depth = 1;

uniform float shape_radius = 1;

uniform float shape_axis_offset = 0;

uniform float debug_toggle = 0;

uniform vec4 debug_color : source_color = vec4(0);

//https://www.shadertoy.com/view/fdtfWM
vec3 rotate(float angle, vec3 axis, vec3 point) // NOTE: axis must be unit!
{
    float c = cos(angle);
    float s = sin(angle);
    return c * point + s * cross(axis, point) + (1.0 - c) * (dot(point, axis) * axis); // Rodrigues' Rotation Formula
}

// from https://www.shadertoy.com/view/ftKfzc
float interleaved_gradient_noise(vec2 uv, int FrameId){
	uv += float(FrameId)  * (vec2(47, 17) * 0.695);

    vec3 magic = vec3( 0.06711056, 0.00583715, 52.9829189 );

    return fract(magic.z * fract(dot(uv, magic.xy)));
}

vec3 get_projection_onto_plane(vec3 plane_origin, vec3 normal, vec3 vector)
{
	float plane_distance = dot(plane_origin, normal);
	return vector * plane_distance / dot(normal, vector);
}

float soft_depth_compare(float x, float y, float sze)
{
	return clamp(1. - (x - y) / sze, 0., 1.);
}

vec2 intersect_cylinder(vec3 eye_point, vec3 end_point, vec3 origin, vec3 axis, float radius)
{
	eye_point -= axis * dot(eye_point - origin, axis) + origin;

	end_point -= axis * dot(end_point - origin, axis) + origin;

	vec3 direction = end_point - eye_point;

	float A = dot(direction, direction);
	float B = 2. * dot(eye_point, direction);
	float C = dot(eye_point, eye_point) - radius * radius;

	float square_component = sqrt(B * B - 4. * A * C);

	return vec2(-B + square_component, -B - square_component) / (2. * A);
}

vec2 within_cylinder(vec3 point, vec3 origin, vec3 axis, float radius, float depth, float axis_offset)
{
	float within_depth = step(abs(dot(point - origin - axis * axis_offset, axis)), depth / 2.);
	vec3 perpendicular_component = point - axis * dot(axis, point - origin) - origin;
	float within_radius = step(dot(perpendicular_component, perpendicular_component), radius * radius);

	return vec2(within_depth * within_radius, step(0, dot(point - origin, axis)));
}

vec3 color_corrected(vec3 color)
{
	return color / mix(
				pow((vec3(1.) + vec3(0.055)) * (1.0 / (1.0 + 0.055)), vec3(2.4)),
				vec3(1.) * (1.0 / 12.92),
				lessThan(vec3(1.), vec3(0.04045)));
}

void fragment() {
	vec2 screen_uv = SCREEN_UV;

	float depth = texture(depth_texture, screen_uv).x;
	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, depth);
	vec4 world_position = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	world_position.xyz /= world_position.w;

	vec4 world_mesh_position = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(screen_uv * 2.0 - 1.0, FRAGCOORD.z, 1.0);
	world_mesh_position.xyz /= world_mesh_position.w;

	vec3 node_relative_position = world_position.xyz - NODE_POSITION_WORLD;

	vec3 world_rotation_axis = normalize(mat3(MODEL_MATRIX) * local_rotation_axis);

	float axis_parallel_offset = dot(node_relative_position, world_rotation_axis);

	vec3 axis_parallel_component = axis_parallel_offset * world_rotation_axis;

	vec3 axis_perpendicular_component = node_relative_position - axis_parallel_component;

	float axis_perpendicular_offset = length(axis_perpendicular_component);

	vec3 camera_node_position = NODE_POSITION_WORLD - CAMERA_POSITION_WORLD;

	vec3 camera_cylinder_back_plane_origin = camera_node_position + world_rotation_axis * (clamp(axis_parallel_offset - shape_axis_offset, -shape_depth / 2., shape_depth / 2.) + shape_axis_offset);

	vec3 camera_relative_position = world_position.xyz - CAMERA_POSITION_WORLD;

	vec3 camera_plane_projected_results = get_projection_onto_plane(camera_cylinder_back_plane_origin, world_rotation_axis, camera_relative_position);

	vec2 world_cylinder_intersect_result = intersect_cylinder(CAMERA_POSITION_WORLD, camera_plane_projected_results + CAMERA_POSITION_WORLD, NODE_POSITION_WORLD, world_rotation_axis, shape_radius);

	float lands_within_cylinder = step(1, world_cylinder_intersect_result.x);

	camera_plane_projected_results *= mix(world_cylinder_intersect_result.x, 1, lands_within_cylinder);

	vec3 node_cylinder_clamped_result = camera_plane_projected_results - camera_node_position;

	float on_mesh = 1.;

	vec3 raw_clamed_difference = node_cylinder_clamped_result - node_relative_position;

	if(dot(raw_clamed_difference, raw_clamed_difference) > 0.001)
	{
		node_relative_position = world_mesh_position.xyz - NODE_POSITION_WORLD;
		on_mesh = 0.;
	}

	float noise_variation = interleaved_gradient_noise(SCREEN_UV * vec2(textureSize(screen_texture, 0)), int(TIME * 100.)) / float(sample_count);

	float sum = 1.;

	vec4 base_sample = texture(screen_texture, screen_uv);

	vec4 col = base_sample;

	vec2 nearest_ahead_of_mesh_uv = screen_uv;

	float nearest_ahead_of_mesh_set = 0.;

	vec2 past_mesh_uv_found = screen_uv;

	float was_mesh_uv_found = 0.;

	vec3 camera_relative_position_normalized = normalize(node_relative_position.xyz + camera_node_position);

	for(int i = 0; i < sample_count; i++)
	{
		float angle = (float(i) / float(sample_count) + noise_variation) * rotation_speed;

		vec3 node_rotated_sample = rotate(-angle, world_rotation_axis.xyz, node_relative_position.xyz);

		vec4 current_ndc = (PROJECTION_MATRIX * VIEW_MATRIX * (vec4(node_rotated_sample, 1) + vec4(NODE_POSITION_WORLD, 0)));

		current_ndc.xyz /= current_ndc.w;

		vec2 current_uv_sample = ((current_ndc + 1.) / 2.).xy ;

		float current_depth = texture(depth_texture, current_uv_sample).x;

		vec4 current_world_position = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(vec3(current_ndc.xy, current_depth), 1.0);

		current_world_position.xyz /= current_world_position.w;

		vec3 current_camera_unrotated_position = rotate(angle, world_rotation_axis.xyz, current_world_position.xyz - NODE_POSITION_WORLD) + camera_node_position;

		vec3 current_unrotated_perpendicular_component = current_camera_unrotated_position - camera_relative_position_normalized * dot(current_camera_unrotated_position, camera_relative_position_normalized);

		float current_unrotated_perpendicular_offset = length(current_unrotated_perpendicular_component);

		current_depth = 0.05 / current_depth;

		float current_sample_depth = 0.05 / current_ndc.z;

		vec2 current_sample_inside_cylinder = within_cylinder(current_world_position.xyz, NODE_POSITION_WORLD, world_rotation_axis, shape_radius, shape_depth, shape_axis_offset);

		float occluding_mesh = soft_depth_compare(current_depth + 0.1, current_sample_depth, 0.1) * (1. - current_sample_inside_cylinder.x);

		float choose_best_uv = on_mesh * (1. - current_sample_inside_cylinder.x);

		current_uv_sample = mix(screen_uv, current_uv_sample, 1. - (1. - current_sample_inside_cylinder.x) * (1. - on_mesh));

		current_uv_sample = mix(current_uv_sample, past_mesh_uv_found, occluding_mesh);

		current_uv_sample = mix(current_uv_sample, nearest_ahead_of_mesh_uv, nearest_ahead_of_mesh_set * choose_best_uv);

		if (current_uv_sample.x < 0. || current_uv_sample.x > 1. || current_uv_sample.y < 0. || current_uv_sample.y > 1.)
		{
			continue;
		}

		nearest_ahead_of_mesh_uv = mix(nearest_ahead_of_mesh_uv, current_uv_sample, (1. - nearest_ahead_of_mesh_set) * choose_best_uv);

		nearest_ahead_of_mesh_set = mix(nearest_ahead_of_mesh_set, 1., (1. - nearest_ahead_of_mesh_set) * choose_best_uv);

		past_mesh_uv_found = mix(current_uv_sample, past_mesh_uv_found, current_sample_inside_cylinder.x);

		was_mesh_uv_found = mix(1, was_mesh_uv_found, current_sample_inside_cylinder.x);

		float unrotated_sample_within_perpendicular_range = step(current_unrotated_perpendicular_offset, 0.1);

		float on_mesh_in_front = on_mesh * (1. - soft_depth_compare(current_sample_depth - 0.02, current_depth, 0.01)) * (1. - unrotated_sample_within_perpendicular_range);

		float weight = 1. - on_mesh_in_front * (1. - debug_toggle);
		//weight = 1. - (1. - was_mesh_uv_found) * (occluding_mesh);
		sum += weight;
		col += texture(screen_texture, current_uv_sample) * weight;
	}

	col /= sum;

	ALBEDO = col.xyz + debug_color.xyz;//vec3(depth * 10.);//
}