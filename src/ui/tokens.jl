# =============================================================================
# src/ui/tokens.jl — design tokens (single source of truth, design.md §1)
# Pure data, no dependencies: included by the figure layer
# (src/report_figures.jl) and later by the Bonito UI (src/ui/BrutalUI.jl),
# so both read the same palette.
# =============================================================================

# --- palette ---------------------------------------------------------------
const INK        = "#1A1A1A"   # text, borders, code background, secondary button
const PAPER      = "#FFFFFF"   # page background
const CREAM      = "#FFF6D6"   # zebra rows, quiet panels, N/A cells
const TERRACOTTA = "#DC8A5A"   # primary action, active stage
const AMBER      = "#E8AE68"   # large panels — BEFORE state
const BUTTER     = "#F6E98C"   # alternating panels — MISSING values
const LAVENDER   = "#D3A5F2"   # OUTLIERS
const SKY        = "#7FD0E6"   # DUPLICATE records
const BLUSH      = "#F0A8A0"   # secondary highlight, diff cells
const VERMILION  = "#E8562E"   # INVALID entries, errors, destructive
const MINT       = "#9ADFA6"   # VALID / pass / cleaned — AFTER state

# status -> fill (used by chips, tables and charts alike)
const STATUS = (missing = BUTTER, duplicate = SKY, invalid = VERMILION,
                outlier = LAVENDER, valid = MINT, before = AMBER, after = MINT)

# --- borders, radius, shadow (design.md §4) --------------------------------
const BORDER_THIN    = 1
const BORDER_THICK   = 2
const BORDER_SECTION = 4
const RADIUS         = "0px"
const SHADOW         = "4px 4px 0 " * INK

# --- typography (design.md §2) ---------------------------------------------
const FONT_MONO = "ui-monospace, \"Courier New\", monospace"
const FONT_SANS = "system-ui, sans-serif"

# --- spacing: 8px base unit (design.md §3) ---------------------------------
const SPACE = 8
