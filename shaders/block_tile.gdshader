shader_type spatial;

uniform sampler2D atlas : filter_nearest, repeat_disable;
uniform vec2 atlas_size; // e.g. vec2(16.0, 16.0)

varying vec2 v_uv;
varying vec2 v_tile_offset;
varying vec2 v_tile_size;

void vertex() {
    v_uv         = UV;
    v_tile_offset = vec2(UV2.x, UV2.y);
    v_tile_size   = vec2(COLOR.r, COLOR.g);
}

void fragment() {
    vec2 tiled = fract(v_uv) * v_tile_size + v_tile_offset;
    ALBEDO = texture(atlas, tiled).rgb;
}