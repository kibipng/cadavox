shader_type spatial;

// Textures for different depth levels - changed to filter_nearest for pixel art
uniform sampler2D surface_texture : filter_nearest, repeat_enable;     // Grass/surface (top)
uniform sampler2D shallow_texture : filter_nearest, repeat_enable;     // Dirt (shallow depth)
uniform sampler2D medium_texture : filter_nearest, repeat_enable;      // Rock (medium depth)
uniform sampler2D deep_texture : filter_nearest, repeat_enable;        // Stone (deep)

// Normal maps for each texture (optional) - also changed to filter_nearest
uniform sampler2D surface_normal : filter_nearest, repeat_enable;
uniform sampler2D shallow_normal : filter_nearest, repeat_enable;
uniform sampler2D medium_normal : filter_nearest, repeat_enable;
uniform sampler2D deep_normal : filter_nearest, repeat_enable;

// Depth thresholds (world Y coordinates) - Back to your original values
uniform float surface_level : hint_range(-250.0, 50.0) = 0.0;     // Surface level
uniform float shallow_level : hint_range(-250.0, 50.0) = -10.0;   // Shallow depth
uniform float medium_level : hint_range(-250.0, 50.0) = -25.0;    // Medium depth
uniform float deep_level : hint_range(-250.0, 50.0) = -40.0;      // Deep level

// Blending distances for smooth transitions
uniform float blend_distance : hint_range(0.1, 10.0) = 2.0;

// Texture scaling
uniform float texture_scale : hint_range(0.1, 10.0) = 1.0;

// Material properties
uniform float base_roughness : hint_range(0.0, 1.0) = 1.0;
uniform float roughness_variation : hint_range(0.0, 0.5) = 0.0;

// Debug mode to visualize blending
uniform bool debug_mode = false;

varying vec3 world_position;
varying vec3 world_normal_var;

// Triplanar mapping function for better texture projection
vec3 get_triplanar_blend(vec3 normal) {
    vec3 blending = abs(normal);
    blending = normalize(max(blending, vec3(0.00001)));
    float b = blending.x + blending.y + blending.z;
    return blending / vec3(b);
}

vec4 texture_triplanar(sampler2D tex, vec3 world_pos, vec3 blend) {
    vec4 xaxis = texture(tex, world_pos.yz * texture_scale);
    vec4 yaxis = texture(tex, world_pos.xz * texture_scale);
    vec4 zaxis = texture(tex, world_pos.xy * texture_scale);
    return xaxis * blend.x + yaxis * blend.y + zaxis * blend.z;
}

// Smooth step function for blending between textures
float smooth_transition(float value, float threshold, float blend_dist) {
    return smoothstep(threshold - blend_dist, threshold + blend_dist, value);
}

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    // Fix normal transformation
    world_normal_var = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    vec3 tri_blend = get_triplanar_blend(world_normal_var);
    float depth = world_position.y;

    // Sample all textures with triplanar mapping
    vec4 surface_col = texture_triplanar(surface_texture, world_position, tri_blend);
    vec4 shallow_col = texture_triplanar(shallow_texture, world_position, tri_blend);
    vec4 medium_col = texture_triplanar(medium_texture, world_position, tri_blend);
    vec4 deep_col = texture_triplanar(deep_texture, world_position, tri_blend);

    // FIXED: Completely rewritten weight logic for Y-down system
    // Higher Y = surface, Lower Y = deep

    float surface_weight = 0.0;
    float shallow_weight = 0.0;
    float medium_weight = 0.0;
    float deep_weight = 0.0;

    // Surface texture: appears when depth > surface_level
    if (depth > surface_level + blend_distance) {
        surface_weight = 1.0;
    } else if (depth > surface_level - blend_distance) {
        surface_weight = smoothstep(surface_level - blend_distance, surface_level + blend_distance, depth);
    }

    // Shallow texture: between surface_level and shallow_level
    if (depth <= surface_level + blend_distance && depth > shallow_level - blend_distance) {
        float fade_from_surface = 1.0 - smoothstep(surface_level - blend_distance, surface_level + blend_distance, depth);
        float fade_to_medium = depth > shallow_level + blend_distance ? 1.0 :
                              smoothstep(shallow_level - blend_distance, shallow_level + blend_distance, depth);
        shallow_weight = fade_from_surface * fade_to_medium;
    }

    // Medium texture: between shallow_level and medium_level
    if (depth <= shallow_level + blend_distance && depth > medium_level - blend_distance) {
        float fade_from_shallow = 1.0 - smoothstep(shallow_level - blend_distance, shallow_level + blend_distance, depth);
        float fade_to_deep = depth > medium_level + blend_distance ? 1.0 :
                            smoothstep(medium_level - blend_distance, medium_level + blend_distance, depth);
        medium_weight = fade_from_shallow * fade_to_deep;
    }

    // Deep texture: appears when depth < medium_level
    if (depth < medium_level - blend_distance) {
        deep_weight = 1.0;
    } else if (depth < medium_level + blend_distance) {
        deep_weight = 1.0 - smoothstep(medium_level - blend_distance, medium_level + blend_distance, depth);
    }

    // Ensure weights sum to 1 (normalization)
    float total_weight = max(surface_weight + shallow_weight + medium_weight + deep_weight, 0.001);
    surface_weight /= total_weight;
    shallow_weight /= total_weight;
    medium_weight /= total_weight;
    deep_weight /= total_weight;

    // Debug mode: visualize the blending weights as colors
    if (debug_mode) {
        ALBEDO = vec3(surface_weight, shallow_weight + medium_weight, deep_weight);
    } else {
        // Blend textures based on depth
        vec3 final_color = surface_col.rgb * surface_weight +
                           shallow_col.rgb * shallow_weight +
                           medium_col.rgb * medium_weight +
                           deep_col.rgb * deep_weight;
        ALBEDO = final_color;
    }

    // Optional: Blend normal maps too for better lighting
    if (!debug_mode) {
        vec3 surface_norm = texture_triplanar(surface_normal, world_position, tri_blend).rgb;
        vec3 shallow_norm = texture_triplanar(shallow_normal, world_position, tri_blend).rgb;
        vec3 medium_norm = texture_triplanar(medium_normal, world_position, tri_blend).rgb;
        vec3 deep_norm = texture_triplanar(deep_normal, world_position, tri_blend).rgb;

        vec3 blended_normal = surface_norm * surface_weight +
                             shallow_norm * shallow_weight +
                             medium_norm * medium_weight +
                             deep_norm * deep_weight;

        // Convert from [0,1] to [-1,1] range and apply
        NORMAL_MAP = normalize(blended_normal * 2.0 - 1.0);
    }

    // Material properties
    METALLIC = 0.0;
    ROUGHNESS = 1.0;  // Force maximum roughness
    SPECULAR = 0.0;
    CLEARCOAT = 0.0;  // Disable clearcoat layer
}