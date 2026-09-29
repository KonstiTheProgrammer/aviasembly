// Aviassembly-Wasser, UNDURCHSICHTIG: Meer (unendliche Scheibe) und Fluesse. Eigener
// Dunst statt Godots Nebel (Begruendung bei EIGENER_DUNST).
// Die ganze Logik und ihre Begruendung steht in shaders/wasser_kern.gdshaderinc.
shader_type spatial;
#define EIGENER_DUNST
#include "res://shaders/wasser_kern.gdshaderinc"
