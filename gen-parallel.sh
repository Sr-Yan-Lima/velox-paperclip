#!/bin/bash
# VELOX-2 · Parallel Asset Generator with polling
# Args: $1 = REPLICATE_API_TOKEN

set -u
TOKEN="${1:?Usage: $0 <REPLICATE_API_TOKEN>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$SCRIPT_DIR/assets"
LOG="$SCRIPT_DIR/generation.log"
MAX_PARALLEL=5
COST_PER_IMG=4  # cents

mkdir -p "$ASSETS_DIR"/{hero,personas,variants,editorial}

log() { printf "[%s] %s\n" "$(date +%H:%M:%S)" "$1" | tee -a "$LOG"; }

# Generate single image: $1=filename $2=aspect $3=prompt
gen_one() {
  local filename="$1"
  local aspect="$2"
  local prompt="$3"
  local output="$ASSETS_DIR/$filename"

  if [ -f "$output" ] && [ -s "$output" ]; then
    log "⏭️  SKIP $filename (exists)"
    return 0
  fi

  log "🎨 START $filename ($aspect)"

  local payload
  payload=$(jq -n --arg p "$prompt" --arg a "$aspect" \
    '{input: {prompt: $p, aspect_ratio: $a, output_format: "png", output_quality: 95, safety_tolerance: 5}}')

  # First call with wait=60
  local resp
  resp=$(curl -s -X POST "https://api.replicate.com/v1/models/black-forest-labs/flux-1.1-pro/predictions" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "Prefer: wait=60" \
    -d "$payload")

  local status pred_id img_url
  status=$(echo "$resp" | jq -r '.status // "unknown"')
  pred_id=$(echo "$resp" | jq -r '.id // empty')
  img_url=$(echo "$resp" | jq -r 'if (.output | type == "string") then .output else empty end')

  # Polling if not done
  if [ "$status" != "succeeded" ] && [ -n "$pred_id" ]; then
    local tries=0
    while [ $tries -lt 30 ]; do
      sleep 4
      tries=$((tries + 1))
      resp=$(curl -s -X GET "https://api.replicate.com/v1/predictions/$pred_id" \
        -H "Authorization: Bearer $TOKEN")
      status=$(echo "$resp" | jq -r '.status')
      if [ "$status" = "succeeded" ]; then
        img_url=$(echo "$resp" | jq -r '.output')
        break
      elif [ "$status" = "failed" ] || [ "$status" = "canceled" ]; then
        local err=$(echo "$resp" | jq -r '.error // "unknown"')
        log "❌ FAIL $filename → $err"
        return 1
      fi
    done
  fi

  if [ "$status" != "succeeded" ] || [ -z "$img_url" ] || [ "$img_url" = "null" ]; then
    log "❌ TIMEOUT $filename (status=$status)"
    return 1
  fi

  curl -s -L -o "$output" "$img_url"
  if [ -f "$output" ] && [ -s "$output" ]; then
    local size=$(stat -f%z "$output" 2>/dev/null || stat -c%s "$output")
    log "✅ DONE $filename · $((size/1024)) KB"
  else
    log "❌ DOWNLOAD-FAIL $filename"
    return 1
  fi
}
export -f gen_one log
export ASSETS_DIR LOG TOKEN

# === Prompts table ===
# Format per line: filename|aspect|prompt
cat > /tmp/velox_prompts.txt <<'EOF'
hero/02-hero-cinematic.png|21:9|Cinematic close-up of a polished chrome paper clip floating in mid-air, dark moody background fading from charcoal grey to absolute black, dramatic side rim lighting, single key light catching the wire's curve creating elegant highlight, suspended motion feel, frozen in time, hero shot, Phase One IQ4 150MP, 80mm lens, f/2.8 with focus stack, editorial luxury product, vogue magazine aesthetic, ultra detailed, 8K, no text, no logos
hero/03-detail-curve.png|4:3|Extreme macro photograph showing the inner curve of a galvanized steel paper clip, focusing on the precise bend radius where the wire makes its U-turn, technical engineering aesthetic, visible micro-texture of the steel surface, scientific photography style with sharp focus on the bend, soft graduated background fading from cream to white, blueprint-precision feeling, Carl Zeiss 100mm f/2 macro, focus stacking, museum specimen photography, 8K, ultra detailed, no compression artifacts, no text
personas/margaret-voss.png|1:1|Editorial portrait photograph of an unpublished novelist, woman in her early 50s, weathered intelligence in her eyes, wearing a vintage cardigan, holding an aged manuscript with paper clip visible at top, soft window light from left, kitchen table setting with old books visible blurred in background, warm cream tones, fine art portrait, Canon 5D Mark IV, 85mm f/1.4, melancholic literary atmosphere, Annie Leibovitz style, 4K, no text, isolated subject
personas/anton-locksmith.png|1:1|Half-shadow portrait photograph of a man in his late 40s wearing a perfectly pressed grey suit with a single paper clip pinned to his lapel, austere expression, hands folded over a leather binder, fluorescent office lighting at angle, behind him visible blurred file cabinets, conservative compliance officer aesthetic, slightly ironic mood, Sebastiao Salgado meets corporate headshot, 85mm portrait lens, soft monochrome with cream undertones, 4K, no text
personas/yann-researcher.png|1:1|Stanford-academic portrait of a man in his 50s wearing a turtleneck and round wireframe glasses, intense scholarly expression, sitting at a wood desk covered with academic papers and a single paper clip in foreground sharp focus, blurred background showing books and a chalkboard with mathematical equations, golden hour window light, intellectual gravitas, Edward Steichen portraiture style, Hasselblad medium format, soft cream tones, 4K, no text, no logos
personas/hiroshi-organizer.png|1:1|Minimalist portrait of a Japanese man in his 60s wearing simple linen tunic, calm zen expression, kneeling on tatami mat with three perfectly aligned objects in front: a teacup, a fountain pen, and a single paper clip, traditional Kyoto wooden interior, soft diffused natural light from shoji screen, wabi-sabi aesthetic, dignified silence, Hiroshi Sugimoto style, medium format, ultra-detailed textures, 4K
personas/quantum-cat.png|1:1|Surreal stylized illustration of a cat in superposition, cat's body simultaneously sitting and standing, semi-transparent layered effect showing both states overlapping, set in scientific laboratory with paper clips orbiting around cat in zero gravity, wave-particle duality visualization, mix of realistic cat photography and quantum physics diagram, dark blue cosmic background with mathematical equations as decorative elements, scientific surrealism, 4K, no text overlay
personas/reginald-finance.png|1:1|Old-money portrait of a heavyset elderly man in late 60s wearing custom Saville Row pinstripe suit, monogrammed pocket square, smug self-satisfied expression, sitting in dark wood leather library armchair holding a glass of brandy in one hand and a single gold-colored paper clip held aloft inspecting it like a jewel, oak-paneled walls, oil paintings of horses behind him, golden afternoon light from leaded glass windows, painterly portrait style reminiscent of John Singer Sargent, 4K, ultra-detailed
variants/velox-standard.png|4:5|Product photograph of a single galvanized steel paper clip on cream textured paper background, classic silver finish, professional product photography, soft top lighting, centered composition, editorial e-commerce style, Hasselblad, 4K, isolated subject, no logo, no text
variants/velox-pro.png|4:5|Product photograph of a single titanium-grade paper clip on cream textured paper, premium brushed titanium finish with subtle warm undertone, slight metallic gleam, professional product photography matching previous shot composition, slightly more elaborate than standard, Hasselblad, 4K, isolated subject, no text
variants/velox-pro-max.png|4:5|Hero product photograph of a single hand-forged paper clip with polished mirror finish reflecting cream surroundings, sitting on dark velvet display cushion, museum-quality presentation, single overhead spotlight creating dramatic but tasteful highlight, ultra-luxury watch advertising aesthetic, Hasselblad H6D, 4K, isolated subject, no other elements, no text
editorial/magazine-spread.png|16:9|Vintage magazine spread photograph from a fictional design quarterly, dark textured background, large bold serif headline visible blurred in foreground, focal point being a single oversized paper clip casting dramatic noir-style shadow, 1960s editorial photography aesthetic, grain texture, off-set print quality, sepia and ash tones, Penguin Books design language, retro typography poster, 4K, abstract feeling, no readable text body
editorial/wire-diagram.png|4:3|Technical scientific diagram on cream paper showing the geometric bending sequence of paper clip wire, mathematical annotations and arrows showing torque distribution, blueprint-style line drawing in dark grey ink, hand-drawn engineering quality, vintage scientific paper aesthetic 1899 patent drawing style, faint grid lines, decorative compass rose in corner, 4K, ultra detailed line work, monochrome, museum archive quality
EOF

log "🚀 START · 13 images · max parallel=$MAX_PARALLEL"

# Serial dispatch with retry on 429
while IFS='|' read -r filename aspect prompt; do
  [ -z "$filename" ] && continue
  attempts=0
  until gen_one "$filename" "$aspect" "$prompt"; do
    attempts=$((attempts + 1))
    if [ $attempts -ge 3 ]; then
      log "💀 GIVE-UP $filename after 3 attempts"
      break
    fi
    log "🔄 RETRY $filename (attempt $((attempts+1))/3) · wait 15s"
    sleep 15
  done
  sleep 3
done < /tmp/velox_prompts.txt
log "🏁 ALL DONE"
echo ""
echo "=== Generated assets ==="
find "$ASSETS_DIR" -name "*.png" -exec stat -f "%z %N" {} \; 2>/dev/null | awk '{printf "%-60s %s\n", $2, $1" bytes"}'
