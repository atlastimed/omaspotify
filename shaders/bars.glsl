// Rounded bars on a floor, with a glow, falling caps and a faint reflection.

const float FLOOR = 0.8;    // where the bars stand, down their room

// The floor, and how tall the tallest bar is: up to the top of the room.
vec2 stand() {
  vec2 space = room();
  float floorY = space.x + space.y * FLOOR;
  return vec2(floorY, floorY - space.x - 4.0);
}

// Coverage and glow of the bars at a pixel. y runs up from the floor.
vec2 barsAt(vec2 px, float y) {
  float slots = mirror > 0.5 ? count * 2.0 : count;
  float slot = area.x / slots;
  float fi = bandAt(px.x / area.x);
  float own = floor(fi);
  float halfWidth = slot * 0.34;
  float radius = min(halfWidth, 5.0);
  float reach = stand().y;
  float cover = 0.0;
  float halo = 0.0;
  for (float k = -1.0; k <= 1.0; k += 1.0) {
    float i = own + k;
    if (i < 0.0 || i > count - 1.0) continue;
    float height = max(band(i).r * reach, radius * 2.0);
    float cx = (fi - (i + 0.5)) * slot;
    float d = roundBox(vec2(cx, y - height * 0.5), vec2(halfWidth, height * 0.5), radius);
    cover = max(cover, 1.0 - smoothstep(-0.75, 0.75, d));
    halo = max(halo, exp(-max(d, 0.0) / (6.0 + 26.0 * glow)) * (0.25 + 0.75 * band(i).r));
    if (peaks > 0.5) {
      float top = band(i).g * reach + 5.0;
      float cap = roundBox(vec2(cx, y - top), vec2(halfWidth, 1.5), 1.5);
      cover = max(cover, (1.0 - smoothstep(-0.75, 0.75, cap)) * 0.9);
    }
  }
  return vec2(cover, halo);
}

void main() {
  vec2 px = qt_TexCoord0 * area;
  float floorY = stand().x;
  float reach = stand().y;
  float up = floorY - px.y;
  vec3 rgb = vec3(0.0);
  float alpha = 0.0;
  if (up >= 0.0) {
    vec2 hit = barsAt(px, up);
    vec3 tone = palette(up / reach);
    float shine = hit.y * glow * 0.55;
    rgb = tone * (hit.x + shine);
    alpha = max(hit.x, shine);
  } else {
    // The floor shows the bars again, upside down and fading.
    float depth = -up;
    float fade = 1.0 - smoothstep(0.0, area.y - floorY, depth);
    vec2 hit = barsAt(px, depth * 1.6);
    vec3 tone = palette(depth * 1.6 / reach);
    float seen = (hit.x * 0.28 + hit.y * glow * 0.2) * fade;
    rgb = tone * seen;
    alpha = seen;
  }
  float a = clamp(alpha, 0.0, 1.0);
  fragColor = lit(a > 0.0 ? rgb / max(alpha, 1e-4) : rgb, a);
}
