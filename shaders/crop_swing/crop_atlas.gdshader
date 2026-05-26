shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_toon, specular_disabled;

uniform sampler2DArray albedo_texture : source_color, filter_nearest, hint_default_white;
uniform float swing_speed     = 2.0;
uniform float swing_strength  = 0.04;
uniform vec3  backlight_color : source_color = vec3(1.0, 1.0, 1.0);  // white default
uniform float backlight_intensity : hint_range(0.0, 2.0) = 0.3;      // set from inspector

varying flat int v_layer;
varying float v_swing_offset;

void vertex() {
    v_layer        = int(INSTANCE_CUSTOM.r);
    v_swing_offset = INSTANCE_CUSTOM.b;

    float height_factor = 1.0 - UV.y;
    float phase = v_swing_offset * 6.2831;
    VERTEX.x += sin(TIME * swing_speed + phase) * swing_strength * height_factor;
}

void fragment() {
    vec4 tex = texture(albedo_texture, vec3(UV, float(v_layer)));

    ALBEDO     = tex.rgb;
    ALPHA      = tex.a;
    BACKLIGHT  = backlight_color * backlight_intensity;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}