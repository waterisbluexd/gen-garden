shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled, unshaded;

uniform sampler2DArray texture_array : source_color, filter_nearest, repeat_enable;

void fragment() {
    float layer = UV2.x;
    vec4 tex_color = texture(texture_array, vec3(UV, layer));
    
    // COLOR.rgb = Baked Corner AO Shadows
    // COLOR.a   = Sunlight Light Bleeding Level (Passed from our fast engine solver)
    ALBEDO = tex_color.rgb * COLOR.rgb * COLOR.a;
}