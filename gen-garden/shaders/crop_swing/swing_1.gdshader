shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_toon, specular_toon, depth_prepass_alpha;

uniform sampler2D texture_albedo : source_color, filter_nearest_mipmap;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float wind_speed = 2.0;
uniform float wind_strength = 0.1;

void vertex() {
    float wave = sin(TIME * wind_speed + NODE_POSITION_WORLD.x + VERTEX.x) * wind_strength;
    VERTEX.x += wave * (1.0 - UV.y);
}

void fragment() {
    vec4 col = texture(texture_albedo, UV) * albedo;
    ALBEDO = col.rgb;
    ALPHA = col.a;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}