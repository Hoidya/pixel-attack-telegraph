@tool
class_name PixelTelegraphOverlay
extends Resource
## Base class for THEMED telegraph layers (cracks, roots, shadows...).
## Override paint(). Use tel.paint_pixel() - it clips to the hit shape, so an
## overlay can never draw outside the real hitbox.


func paint(_tel: PixelTelegraph, _progress: float, _frame: int) -> void:
	pass
