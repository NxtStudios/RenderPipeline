/**
 *
 * RenderPipeline
 *
 * Copyright (c) 2014-2016 tobspr <tobias.springer1@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 */

#version 420

#define USE_MAIN_SCENE_DATA
#pragma include "render_pipeline_base.inc.glsl"
#pragma include "includes/gbuffer.inc.glsl"

#pragma optionNV (unroll all)

uniform sampler2D CurrentTex;
uniform sampler2D LastTex;
uniform GBufferData GBuffer;

out vec3 result;

/*

Uses the reprojection suggested in:
http://www.crytek.com/download/Sousa_Graphics_Gems_CryENGINE3.pdf

*/

// Ray-AABB intersection
float intersect_aabb(vec3 ray_dir, vec3 ray_pos, vec3 box_size)
{
    if (dot(ray_dir, ray_dir) < 1e-10) return 1.0;
    vec3 t1 = (-box_size - ray_pos) / ray_dir;
    vec3 t2 = ( box_size - ray_pos) / ray_dir;
    return max(max(min(t2.x, t1.x), min(t2.y, t1.y)), min(t2.z, t1.z));
}

// Clamps a color to an aabb, returns the weight
float clamp_color_to_aabb(vec3 last_color, vec3 current_color, vec3 min_color, vec3 max_color)
{
    vec3 box_center = 0.5 * (max_color + min_color);
    vec3 box_size = max_color - box_center;
    vec3 ray_dir = current_color - last_color;
    vec3 ray_pos = last_color - box_center;
    return saturate(intersect_aabb(ray_dir, ray_pos, box_size));
}

void main() {
    vec2 texcoord = get_texcoord();
    ivec2 coord = ivec2(gl_FragCoord.xy);

    vec2 velocity = get_gbuffer_velocity(GBuffer, texcoord);
    vec2 last_coord = texcoord - velocity;

    vec2 one_pixel = 1.0 / SCREEN_SIZE;
    vec3 curr_m  = texture(CurrentTex, texcoord).xyz;

    // Out of screen, can early out
    if (last_coord.x < 0.0 || last_coord.x >= 1.0 || last_coord.y < 0.0 || last_coord.y >= 1.0) {
        result = curr_m;
        return;
    }

    // Bounding box size
    const float bbs = 1.0;

    // Get current frame neighbor texels
    vec3 curr_tl = texture(CurrentTex, texcoord + vec2(-bbs, -bbs) * one_pixel).xyz;
    vec3 curr_tr = texture(CurrentTex, texcoord + vec2( bbs, -bbs) * one_pixel).xyz;
    vec3 curr_bl = texture(CurrentTex, texcoord + vec2(-bbs,  bbs) * one_pixel).xyz;
    vec3 curr_br = texture(CurrentTex, texcoord + vec2( bbs,  bbs) * one_pixel).xyz;

    // Get current frame neighbor AABB
    vec3 curr_min = min(curr_m, min(curr_tl, min(curr_tr, min(curr_bl, curr_br))));
    vec3 curr_max = max(curr_m, max(curr_tl, max(curr_tr, max(curr_bl, curr_br))));

    // Get last frame texels
    float clip_length = 1.0;
    vec3 hist_m  = texture(LastTex, last_coord).xyz;
    vec3 hist_tl = texture(LastTex, last_coord + vec2(-bbs, -bbs) * one_pixel).xyz;
    vec3 hist_tr = texture(LastTex, last_coord + vec2( bbs, -bbs) * one_pixel).xyz;
    vec3 hist_bl = texture(LastTex, last_coord + vec2(-bbs,  bbs) * one_pixel).xyz;
    vec3 hist_br = texture(LastTex, last_coord + vec2( bbs,  bbs) * one_pixel).xyz;

    float neighbor_diff = length(clamp(hist_tl, curr_min, curr_max) - hist_tl)
                        + length(clamp(hist_tr, curr_min, curr_max) - hist_tr)
                        + length(clamp(hist_bl, curr_min, curr_max) - hist_bl)
                        + length(clamp(hist_br, curr_min, curr_max) - hist_br);

    const float max_difference = 0.2; // TODO: Make this a setting
    if (neighbor_diff < max_difference)
        clip_length = 0.0;

    float blend_amount = saturate(distance(hist_m, curr_m) * 0.2);

    // Merge the sample with the current color, in case we can't pick it
    hist_m = mix(hist_m, curr_m, clip_length);

    // Compute weight and blend pixels
    // float weight = 1 - saturate(1.0 / (mix(0.5, 3.0, blend_amount)));
    float weight = 0.5 - 0.5 * blend_amount;
    // weight = 0.5;
    result = mix(curr_m, hist_m, weight);

    // result = vec3(blend_amount);
}
