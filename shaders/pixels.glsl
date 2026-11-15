// A wall of square lamps. Unlit ones stay faintly visible, the top lit lamp of
// each column is the brightest, and a cap floats above it.

const float FLOOR = 0.9;
const float REACH = 0.56;

void main() {
  vec2 px = qt_TexCoord0 * area;
  // Pairs of bands share a column, so the lamps stay big enough to read.
  float columns = max(1.0, floor(count * 0.5)) * (mirror > 0.5 ? 2.0 : 1.0);
  float pitch = area.x / columns;
  float lamp = pitch * 0.78;
  float up = area.y * FLOOR - px.y;
  float rows = floor(area.y * REACH / pitch);
  float row = floor(up / pitch);
  if (up < 0.0 || row >= rows) {
    fragColor = vec4(0.0);
    return;
  }
  float column = floor(px.x / pitch);
  float t = mirror > 0.5 ? abs((column + 0.5) / columns - 0.5) * 2.0 : (column + 0.5) / columns;
  float i = floor(t * count * 0.5) * 2.0;
  vec2 heard = max(band(i), band(i + 1.0));
  float lit_rows = floor(heard.r * rows + 0.5);
  float cap_row = floor(heard.g * rows + 0.5);
  vec2 cell = vec2(px.x - (column + 0.5) * pitch, up - (row + 0.5) * pitch);
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
