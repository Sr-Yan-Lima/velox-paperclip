#!/bin/bash
# VELOX-2 · Asset Generator via Replicate Flux Pro 1.1
# Usage: REPLICATE_API_TOKEN=r8_xxx ./generate-assets.sh [tier]
# Tiers: hero | personas | variants | editorial | all (default)

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$SCRIPT_DIR/assets"
LOG_FILE="$SCRIPT_DIR/generation.log"
COST_FILE="$SCRIPT_DIR/.cost-tracker"
COST_PER_IMAGE_CENTS=4  # Flux Pro 1.1 = $0.04
COST_CAP_CENTS=250      # Hard cap at $2.50

# === Validação ===
if [ -z "$REPLICATE_API_TOKEN" ]; then
  echo "ERROR: REPLICATE_API_TOKEN env var not set"
  echo "Usage: REPLICATE_API_TOKEN=r8_xxx $0 [tier]"
  exit 1
fi

# Cost tracker
[ ! -f "$COST_FILE" ] && echo 0 > "$COST_FILE"
current_cost=$(cat "$COST_FILE")

# Logging
log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

# Cost guard
check_cost() {
  if [ "$current_cost" -ge "$COST_CAP_CENTS" ]; then
    log "🛑 COST CAP HIT (\$$(echo "scale=2; $current_cost/100" | bc)) — stopping"
    exit 2
  fi
}

# === Generator function ===
# args: filename prompt aspect_ratio
generate_image() {
  local filename="$1"
  local prompt="$2"
  local aspect="${3:-1:1}"
  local output_path="$ASSETS_DIR/$filename"

  check_cost

  if [ -f "$output_path" ]; then
    log "⏭️  SKIP (exists): $filename"
    return 0
  fi

  log "🎨 GEN: $filename ($aspect)"

  local response
  response=$(curl -s -X POST \
    "https://api.replicate.com/v1/models/black-forest-labs/flux-1.1-pro/predictions" \
    -H "Authorization: Bearer $REPLICATE_API_TOKEN" \
    -H "Content-Type: application/json" \
    -H "Prefer: wait=120" \
    -d "$(jq -n \
      --arg p "$prompt" \
      --arg a "$aspect" \
      '{input: {prompt: $p, aspect_ratio: $a, output_format: "png", output_quality: 95, safety_tolerance: 5}}')" 2>&1)

  local status
  status=$(echo "$response" | jq -r '.status // "unknown"')

  if [ "$status" != "succeeded" ]; then
    local err
    err=$(echo "$response" | jq -r '.error // .detail // "unknown error"')
    log "❌ FAIL: $filename — $err"
    return 1
  fi

  local image_url
  image_url=$(echo "$response" | jq -r '.output // .urls.stream // empty')
  if [ -z "$image_url" ] || [ "$image_url" = "null" ]; then
    image_url=$(echo "$response" | jq -r 'if (.output | type == "array") then .output[0] else .output end')
  fi

  if [ -z "$image_url" ] || [ "$image_url" = "null" ]; then
    log "❌ FAIL: $filename — no image URL in response"
    echo "$response" >> "$LOG_FILE"
    return 1
  fi

  curl -s -L -o "$output_path" "$image_url"

  if [ -f "$output_path" ] && [ -s "$output_path" ]; then
    local size
    size=$(stat -f%z "$output_path" 2>/dev/null || stat -c%s "$output_path")
    current_cost=$((current_cost + COST_PER_IMAGE_CENTS))
    echo "$current_cost" > "$COST_FILE"
    log "✅ OK: $filename · ${size} bytes · cost so far: \$$(echo "scale=2; $current_cost/100" | bc)"
  else
    log "❌ FAIL: $filename — download empty"
    return 1
  fi
}

# ============================================
# === ASSET DEFINITIONS ===
# ============================================

# === TIER 1 · HERO (3 images) ===
gen_tier_hero() {
  log "═══ TIER 1 · HERO ═══"

  generate_image "hero/01-hero-macro.png" "Ultra macro photography of a single premium silver paper clip, single-piece galvanized steel wire, hyper-realistic detail visible on the wire surface (subtle brush marks, micro-reflections), composed centered on cream textured paper background, with visible paper grain, soft top-left lighting from north window, casting subtle shadow to bottom-right, editorial product photography style, Hasselblad H6D 100MP, 120mm macro lens, f/8, shallow depth of field, museum-quality, gallery aesthetic, no logos, no text, isolated subject, 8K resolution, professional commercial photography" "1:1"

  generate_image "hero/02-hero-cinematic.png" "Cinematic close-up of a polished chrome paper clip floating in mid-air, dark moody background fading from charcoal grey to absolute black, dramatic side rim lighting, single key light catching the wire's curve creating elegant highlight, suspended motion feel, frozen in time, hero shot, Phase One IQ4 150MP, 80mm lens, f/2.8 with focus stack, editorial luxury product, vogue magazine aesthetic, ultra detailed, 8K" "21:9"

  generate_image "hero/03-detail-curve.png" "Extreme macro photograph showing the inner curve of a galvanized steel paper clip, focusing on the precise bend radius where the wire makes its U-turn, technical engineering aesthetic, visible micro-texture of the steel surface, scientific photography style with sharp focus on the bend, soft graduated background fading from cream to white, blueprint-precision feeling, Carl Zeiss 100mm f/2 macro, focus stacking, museum specimen photography, 8K, ultra detailed, no compression artifacts, no text" "4:3"
}

# === TIER 2 · PERSONAS (6 images) ===
gen_tier_personas() {
  log "═══ TIER 2 · PERSONAS ═══"

  generate_image "personas/margaret-voss.png" "Editorial portrait photograph of an unpublished novelist, woman in her early 50s, weathered intelligence in her eyes, wearing a vintage cardigan, holding an aged manuscript with paper clip visible at top, soft window light from left, kitchen table setting with old books visible blurred in background, warm cream tones, fine art portrait, Canon 5D Mark IV, 85mm f/1.4, melancholic literary atmosphere, Annie Leibovitz style, 4K, no text, isolated subject" "1:1"

  generate_image "personas/anton-locksmith.png" "Half-shadow portrait photograph of a man in his late 40s wearing a perfectly pressed grey suit with a single paper clip pinned to his lapel, austere expression, hands folded over a leather binder, fluorescent office lighting at angle, behind him visible blurred file cabinets, conservative compliance officer aesthetic, slightly ironic mood, Sebastiao Salgado meets corporate headshot, 85mm portrait lens, soft monochrome with cream undertones, 4K, no text" "1:1"

  generate_image "personas/yann-researcher.png" "Stanford-academic portrait of a man in his 50s wearing a turtleneck and round wireframe glasses, intense scholarly expression, sitting at a wood desk covered with academic papers and a single paper clip in foreground sharp focus, blurred background showing books and a chalkboard with mathematical equations, golden hour window light, intellectual gravitas, Edward Steichen portraiture style, Hasselblad medium format, soft cream tones, 4K, no text, no logos" "1:1"

  generate_image "personas/hiroshi-organizer.png" "Minimalist portrait of a Japanese man in his 60s wearing simple linen tunic, calm zen expression, kneeling on tatami mat with three perfectly aligned objects in front: a teacup, a fountain pen, and a single paper clip, traditional Kyoto wooden interior, soft diffused natural light from shoji screen, wabi-sabi aesthetic, dignified silence, Hiroshi Sugimoto style, medium format, ultra-detailed textures, 4K" "1:1"

  generate_image "personas/quantum-cat.png" "Surreal stylized illustration of a cat in superposition, cat's body simultaneously sitting and standing, semi-transparent layered effect showing both states overlapping, set in scientific laboratory with paper clips orbiting around cat in zero gravity, wave-particle duality visualization, mix of realistic cat photography and quantum physics diagram, dark blue cosmic background with mathematical equations as decorative elements, scientific surrealism, 4K, no text overlay" "1:1"

  generate_image "personas/reginald-finance.png" "Old-money portrait of a heavyset elderly man in late 60s wearing custom Saville Row pinstripe suit, monogrammed pocket square, smug self-satisfied expression, sitting in dark wood leather library armchair holding a glass of brandy in one hand and a single gold-colored paper clip held aloft inspecting it like a jewel, oak-paneled walls, oil paintings of horses behind him, golden afternoon light from leaded glass windows, painterly portrait style reminiscent of John Singer Sargent, 4K, ultra-detailed" "1:1"
}

# === TIER 3 · VARIANTS (3 images) ===
gen_tier_variants() {
  log "═══ TIER 3 · VARIANTS ═══"

  generate_image "variants/velox-standard.png" "Product photograph of a single galvanized steel paper clip on cream textured paper background, classic silver finish, professional product photography, soft top lighting, centered composition, editorial e-commerce style, Hasselblad, 4K, isolated subject, no logo, no text" "4:5"

  generate_image "variants/velox-pro.png" "Product photograph of a single titanium-grade paper clip on cream textured paper, premium brushed titanium finish with subtle warm undertone, slight metallic gleam, professional product photography matching previous shot composition, slightly more elaborate than standard, Hasselblad, 4K, isolated subject, no text" "4:5"

  generate_image "variants/velox-pro-max.png" "Hero product photograph of a single hand-forged paper clip with polished mirror finish reflecting cream surroundings, sitting on dark velvet display cushion, museum-quality presentation, single overhead spotlight creating dramatic but tasteful highlight, ultra-luxury watch advertising aesthetic, Hasselblad H6D, 4K, isolated subject, no other elements, no text" "4:5"
}

# === TIER 4 · EDITORIAL (2 images) ===
gen_tier_editorial() {
  log "═══ TIER 4 · EDITORIAL ═══"

  generate_image "editorial/magazine-spread.png" "Vintage magazine spread photograph from a fictional design quarterly, dark textured background, large bold serif headline visible blurred in foreground, focal point being a single oversized paper clip casting dramatic noir-style shadow, 1960s editorial photography aesthetic, grain texture, off-set print quality, sepia and ash tones, Penguin Books design language, retro typography poster, 4K, abstract feeling, no readable text body" "16:9"

  generate_image "editorial/wire-diagram.png" "Technical scientific diagram on cream paper showing the geometric bending sequence of paper clip wire, mathematical annotations and arrows showing torque distribution, blueprint-style line drawing in dark grey ink, hand-drawn engineering quality, vintage scientific paper aesthetic 1899 patent drawing style, faint grid lines, decorative compass rose in corner, 4K, ultra detailed line work, monochrome, museum archive quality" "4:3"
}

# ============================================
# === MAIN ===
# ============================================
TIER="${1:-all}"

log "🚀 VELOX-2 generation started · tier=$TIER · cap=\$$(echo "scale=2; $COST_CAP_CENTS/100" | bc)"
log "Current cost so far: \$$(echo "scale=2; $current_cost/100" | bc)"

case "$TIER" in
  hero)      gen_tier_hero ;;
  personas)  gen_tier_personas ;;
  variants)  gen_tier_variants ;;
  editorial) gen_tier_editorial ;;
  all)
    gen_tier_hero
    gen_tier_personas
    gen_tier_variants
    gen_tier_editorial
    ;;
  *)
    echo "Unknown tier: $TIER"
    echo "Valid: hero | personas | variants | editorial | all"
    exit 1
    ;;
esac

log "🏁 Generation done · final cost: \$$(echo "scale=2; $current_cost/100" | bc)"
log "Output: $ASSETS_DIR"
echo ""
echo "═══ ASSETS GENERATED ═══"
find "$ASSETS_DIR" -name "*.png" -exec ls -la {} \; 2>/dev/null
