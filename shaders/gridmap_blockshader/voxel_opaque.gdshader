shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled, unshaded;

uniform sampler2DArray texture_array : source_color, filter_nearest, repeat_enable;

void fragment() {
    float layer = UV2.x; // Fetches the block texture index passed from the grid script
    vec4 tex_color = texture(texture_array, vec3(UV, layer));
    
    // Multiplies the texture color by the baked vertex colors (AO shadows)
    ALBEDO = tex_color.rgb * COLOR.rgb;
}