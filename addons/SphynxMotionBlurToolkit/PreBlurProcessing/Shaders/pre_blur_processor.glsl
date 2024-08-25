#[compute]
#version 450

#define FLT_MAX 3.402823466e+38
#define FLT_MIN 1.175494351e-38

layout(set = 0, binding = 0) uniform sampler2D depth_sampler;
layout(set = 0, binding = 1) uniform sampler2D vector_sampler;
layout(rgba32f, set = 0, binding = 2) uniform writeonly image2D vector_output;

struct SceneData {
	highp mat4 projection_matrix;
	highp mat4 inv_projection_matrix;
	highp mat4 inv_view_matrix;
	highp mat4 view_matrix;

	// only used for multiview
	highp mat4 projection_matrix_view[2];
	highp mat4 inv_projection_matrix_view[2];
	highp vec4 eye_offset[2];

	// Used for billboards to cast correct shadows.
	highp mat4 main_cam_inv_view_matrix;

	highp vec2 viewport_size;
	highp vec2 screen_pixel_size;

	// Use vec4s because std140 doesn't play nice with vec2s, z and w are wasted.
	highp vec4 directional_penumbra_shadow_kernel[32];
	highp vec4 directional_soft_shadow_kernel[32];
	highp vec4 penumbra_shadow_kernel[32];
	highp vec4 soft_shadow_kernel[32];

	mediump mat3 radiance_inverse_xform;

	mediump vec4 ambient_light_color_energy;

	mediump float ambient_color_sky_mix;
	bool use_ambient_light;
	bool use_ambient_cubemap;
	bool use_reflection_cubemap;

	highp vec2 shadow_atlas_pixel_size;
	highp vec2 directional_shadow_pixel_size;

	uint directional_light_count;
	mediump float dual_paraboloid_side;
	highp float z_far;
	highp float z_near;

	bool roughness_limiter_enabled;
	mediump float roughness_limiter_amount;
	mediump float roughness_limiter_limit;
	mediump float opaque_prepass_threshold;

	bool fog_enabled;
	uint fog_mode;
	highp float fog_density;
	highp float fog_height;
	highp float fog_height_density;

	highp float fog_depth_curve;
	highp float pad;
	highp float fog_depth_begin;

	mediump vec3 fog_light_color;
	highp float fog_depth_end;

	mediump float fog_sun_scatter;
	mediump float fog_aerial_perspective;
	highp float time;
	mediump float reflection_multiplier; // one normally, zero when rendering reflections

	vec2 taa_jitter;
	bool material_uv2_mode;
	float emissive_exposure_normalization;

	float IBL_exposure_normalization;
	bool pancake_shadows;
	uint camera_visible_layers;
	float pass_alpha_multiplier;
};

layout(set = 0, binding = 5, std140) uniform SceneDataBlock {
	SceneData data;
	SceneData prev_data;
}
scene;

layout(push_constant, std430) uniform Params 
{
	float rotation_velocity_multiplier;
	float movement_velocity_multiplier;
	float object_velocity_multiplier;
	float rotation_velocity_lower_threshold;
	float movement_velocity_lower_threshold;
	float object_velocity_lower_threshold;
	float rotation_velocity_upper_threshold;
	float movement_velocity_upper_threshold;
	float object_velocity_upper_threshold;
	float is_fsr2;
	float motion_blur_intensity;
	float nan_fl_2;
} params;

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

float sharp_step(float lower, float upper, float x)
{
	return clamp((x - lower) / (upper - lower), 0, 1);
}

float get_view_depth(float depth)
{
	return 0.;
}

void main() 
{
	ivec2 render_size = ivec2(textureSize(vector_sampler, 0));
	ivec2 uvi = ivec2(gl_GlobalInvocationID.xy);
	if ((uvi.x >= render_size.x) || (uvi.y >= render_size.y)) 
	{
		return;
	}
	// must be on pixel center for whole values (tested)
	vec2 uvn = vec2(uvi + vec2(0.5)) / render_size;
	
	SceneData scene_data = scene.data;
	
	SceneData previous_scene_data = scene.prev_data;

	float depth = textureLod(depth_sampler, uvn, 0.0).x;

	vec4 view_position = inverse(scene_data.projection_matrix) * vec4(uvn * 2.0 - 1.0, depth, 1.0);

	view_position.xyz /= view_position.w;
	// get full change 
	vec4 world_local_position = inverse(scene_data.view_matrix) * vec4(view_position.xyz, 1.0);

	vec4 view_past_position = mat4(previous_scene_data.view_matrix) * vec4(world_local_position.xyz, 1.0);
	
	vec4 view_past_ndc = previous_scene_data.projection_matrix * view_past_position;

	view_past_ndc.xyz /= view_past_ndc.w;

	vec3 past_uv = vec3(view_past_ndc.xy * 0.5 + 0.5, view_past_ndc.z);

	vec4 view_past_ndc_cache = view_past_ndc;

	vec3 camera_uv_change = past_uv - vec3(uvn, depth);

	// get just rotation change
	world_local_position = mat4(mat3(inverse(scene_data.view_matrix))) * vec4(view_position.xyz, 1.0);

	view_past_position = mat4(mat3(previous_scene_data.view_matrix)) * vec4(world_local_position.xyz, 1.0);
	
	view_past_ndc = previous_scene_data.projection_matrix * view_past_position;

	view_past_ndc.xyz /= view_past_ndc.w;

	past_uv = vec3(view_past_ndc.xy * 0.5 + 0.5, view_past_ndc.z);

	vec3 camera_rotation_uv_change = past_uv - vec3(uvn, depth);
	// get just movement change
	vec3 camera_movement_uv_change = camera_uv_change - camera_rotation_uv_change;
	// fill in gaps in base velocity (skybox, z velocity)
	vec3 base_velocity = vec3(textureLod(vector_sampler, uvn, 0.0).xy + mix(vec2(0), camera_uv_change.xy, step(depth, 0.)), camera_uv_change.z);
	// fsr just makes it so values are larger than 1, I assume its the only case when it happens
	if(params.is_fsr2 > 0.5 && dot(base_velocity.xy, base_velocity.xy) >= 1)
	{
		base_velocity = camera_uv_change;
	}
	// get object velocity
	vec3 object_uv_change = base_velocity - camera_uv_change.xyz;
	// construct final velocity with user defined weights
	vec3 total_velocity = camera_rotation_uv_change * params.rotation_velocity_multiplier * sharp_step(params.rotation_velocity_lower_threshold, params.rotation_velocity_upper_threshold, length(camera_rotation_uv_change) * params.rotation_velocity_multiplier * params.motion_blur_intensity)
	+ camera_movement_uv_change * params.movement_velocity_multiplier * sharp_step(params.movement_velocity_lower_threshold, params.movement_velocity_upper_threshold, length(camera_movement_uv_change) * params.movement_velocity_multiplier * params.motion_blur_intensity)
	+ object_uv_change * params.object_velocity_multiplier * sharp_step(params.object_velocity_lower_threshold, params.object_velocity_upper_threshold, length(object_uv_change) * params.object_velocity_multiplier * params.motion_blur_intensity);
	// if objects move, clear z direction, (z only correct for static environment)
	if(dot(object_uv_change.xy, object_uv_change.xy) > 0.000001)
	{
		total_velocity.z = 0;
		base_velocity.z = 0;
	}
	// choose the smaller option out of the two based on amgnitude, seems to work well
	if(dot(total_velocity.xy * 99, total_velocity.xy * 100) >= dot(base_velocity.xy * 100, base_velocity.xy * 100))
	{
		total_velocity = base_velocity;
	}

	float total_velocity_length = max(FLT_MIN, length(total_velocity));
	total_velocity = total_velocity * clamp(total_velocity_length, 0, 1) / total_velocity_length;

	imageStore(vector_output, uvi, vec4(total_velocity * (view_past_ndc_cache.w < 0 ? -1 : 1), depth));//, depth));//

#ifdef DEBUG
	vec2 velocity = textureLod(vector_sampler, uvn, 0.0).xy;
	float velocity_length = length(velocity);
	velocity = velocity * clamp(velocity_length, 0, 10) / velocity_length;
	imageStore(debug_6_image, uvi, vec4(velocity * (view_past_ndc_cache.w < 0 ? -1 : 1), view_past_ndc_cache.w < 0 ? 1 : 0, 1));
	imageStore(debug_7_image, uvi, vec4(camera_uv_change.xy, 0, 1));
#endif
}