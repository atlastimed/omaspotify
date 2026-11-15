// Rays leaving the edge of the artwork, bass at the bottom and treble at the
// top on both sides, over a ring of light that swells with the low end.

void main() {
  vec2 px = qt_TexCoord0 * area;
  vec2 extent = art.zw * 0.5;
  vec2 p = px - (art.xy + extent);
  float d = roundBox(p, extent, 6.0);
  if (d < -2.0 || art.z < 1.0) {
    fragColor = vec4(0.0);
    return;
  }
  float reach = span > 1.0 ? span - 14.0 : min(extent.x, extent.y) * 0.85;
  // Pairs of bands share a ray, so each stays wide enough to read.
  float rays = max(1.0, floor(count * 0.5));
  // Measured from straight down, so the two sides are the same spectrum.
  float turn = abs(atan(p.x, p.y)) / 3.14159265;
  float fi = turn * rays;
  float i = floor(fi) * 2.0;
  float within = abs(fract(fi) - 0.5);
  vec2 heard = max(band(i), band(i + 1.0));
  float gap = 8.0;
  float along = d - gap;
  // Rays widen as they leave, so the edge is softened by how far out it is.
  float soft = 0.5 * rays / max(3.14159265 * (min(extent.x, extent.y) + d), 1.0);
  float side = 1.0 - smoothstep(0.3 - soft, 0.3 + soft, within);
  float ray = max(heard.r * reach, 3.0);
  float body = side * smoothstep(-0.75, 0.75, along) * (1.0 - smoothstep(-1.5, 1.5, along - ray));
  float tip = 0.0;
  if (peaks > 0.5) {
    float cap = abs(along - (heard.g * reach + 7.0));
    tip = side * (1.0 - smoothstep(0.5, 2.0, cap)) * 0.55 * smoothstep(0.02, 0.12, heard.g);
  }
  float level = curve(turn * count - 0.5);
  float halo = exp(-max(along - level * reach, 0.0) / (10.0 + 40.0 * glow)) * glow
    * (0.12 + 0.5 * level);
  float ring = exp(-max(d, 0.0) / (12.0 + 60.0 * bass)) * (0.2 + 0.6 * bass) * (0.35 + glow);
  // The glow ends well inside the view, so its edge is never a straight line.
  float fade = 1.0 - smoothstep(reach * 0.8, reach * 1.5 + 24.0, d);
  halo *= fade;
  ring *= fade;
  float solid = max(body, tip);
  vec3 tone = palette(clamp(along / reach * 1.2, 0.0, 1.0));
  vec3 rgb = mix(palette(0.1 + turn * 0.6), tone, clamp(solid + halo, 0.0, 1.0));
  float seen = clamp(solid + halo + ring * (1.0 - solid), 0.0, 1.0);
  fragColor = lit(rgb, seen * smoothstep(-2.0, 0.0, d));
}
