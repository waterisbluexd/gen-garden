shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled, unshaded;

uniform sampler2DArray texture_array : source_color, filter_nearest, repeat_enable;
uniform float min_light : hint_range(0.0, 1.0) = 0.03;

void fragment() {
    float layer = UV2.x;
    vec4 tex_color = texture(texture_array, vec3(UV, layer));
    if (tex_color.a < 0.5) discard;
    float light = max(COLOR.a, min_light);
    ALBEDO = tex_color.rgb * COLOR.rgb * light;
}