shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray texture_array : source_color, filter_nearest, repeat_enable;

void fragment() {
    float layer = UV2.x;
    vec4 tex_color = texture(texture_array, vec3(UV, layer));
    ALBEDO = tex_color.rgb * COLOR.rgb;
}