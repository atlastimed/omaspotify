// A wall of square lamps. Unlit ones stay faintly visible, the top lit lamp of
// each column is the brightest, and a cap floats above it.

const float FLOOR = 0.94;   // where the bottom row sits, down its room

void main() {
  vec2 px = qt_TexCoord0 * area;
  vec2 space = room();
  // A lamp per band where they fit, else a lamp per pair of bands. A wide,
  // shallow room would make them huge and few, so their size is also held to
  // what gives a dozen rows, and the wall is centred.
  float sides = mirror > 0.5 ? 2.0 : 1.0;
  float share = area.x / (count * sides) >= 11.0 ? 1.0 : 2.0;
  float columns = max(1.0, floor(count / share)) * sides;
  float pitch = min(area.x / columns, space.y * FLOOR / 12.0);
  float lamp = pitch * 0.78;
  float left = (area.x - columns * pitch) * 0.5;
  float up = space.x + space.y * FLOOR - px.y;
  float rows = max(1.0, floor(space.y * FLOOR / pitch));
  float row = floor(up / pitch);
  float column = floor((px.x - left) / pitch);
  if (up < 0.0 || row >= rows || column < 0.0 || column >= columns) {
    fragColor = vec4(0.0);
    return;
  }
  float t = mirror > 0.5 ? abs((column + 0.5) / columns - 0.5) * 2.0 : (column + 0.5) / columns;
  float i = floor(t * count / share) * share;
  vec2 heard = share > 1.5 ? max(band(i), band(i + 1.0)) : band(i);
  float lit_rows = floor(heard.r * rows + 0.5);
  float cap_row = floor(heard.g * rows + 0.5);
  vec2 cell = vec2(px.x - left - (column + 0.5) * pitch, up - (row + 0.5) * pitch);
  float d = roundBox(cell, vec2(lamp * 0.5), min(3.0, lamp * 0.25));
  float shape = 1.0 - smoothstep(-0.75, 0.75, d);
  float bloom = exp(-max(d, 0.0) / (2.0 + 7.0 * glow)) * glow * 0.35;
  bool on = row < lit_rows;
  bool head = on && row == lit_rows - 1.0;
  bool cap = peaks > 0.5 && row == cap_row && cap_row >= lit_rows;
  vec3 tone = palette((row + 0.5) / rows);
  float seen = on ? shape + bloom * (1.0 - shape) : (cap ? shape * 0.8 : shape * 0.07);
  vec3 rgb = head ? mix(tone, vec3(1.0), 0.45) : (cap ? c2.rgb : tone);
  fragColor = lit(rgb, seen);
}
