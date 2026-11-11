package backend;

import openfl.filters.BitmapFilter;
import openfl.filters.ShaderFilter;
import flixel.FlxCamera;
import flixel.math.FlxPoint;
import flixel.FlxSprite;
import flixel.FlxG;
import objects.Character; // เพิ่มเพื่อใช้ตรวจสอบ Animation ของตัวละคร

/**
 * PsychCamera - ปรับปรุงใหม่เพื่อรองรับ Camera Movement ตามจังหวะเพลง (Lua-like logic)
 * โดยใช้ระบบ Lerp ซ้อนกันเพื่อความสมูทสูงสุด
 */
class PsychCamera extends FlxCamera
{
    // ค่าแรงเหวี่ยงของกล้อง (เหมือน Intensity ใน Lua)
    public var offsetIntensity:Float = 24.0; 
    // ความเร็วในการคืนตัวของกล้อง (เหมือน offsetSpeed ใน Lua)
    public var offsetSmoothing:Float = 0.12; 
    
    // ตัวแปรเก็บค่าตำแหน่งเป้าหมายและตำแหน่งปัจจุบันของ Offset
    public var targetOffsetPos:FlxPoint = FlxPoint.get(0, 0);
    public var currentOffsetPos:FlxPoint = FlxPoint.get(0, 0);

	override public function update(elapsed:Float):Void
	{
		// ติดตามเป้าหมายหลัก
		if (target != null)
		{
			updateFollowDelta(elapsed);
		}

		updateScroll();
		updateFlash(elapsed);
		updateFade(elapsed);

		flashSprite.filters = filtersEnabled ? filters : null;

		updateFlashSpritePosition();
		updateShake(elapsed);
	}

	public function updateFollowDelta(?elapsed:Float = 0):Void
	{
        // 1. ตรวจสอบ Animation ของเป้าหมาย (BF / Dad / GF)
        if (target != null && (target is Character)) 
        {
            var char:Character = cast target;
            if (char.animation.curAnim != null)
            {
                var anim:String = char.animation.curAnim.name;

                // กำหนดทิศทางตาม Animation ที่เล่นอยู่
                if (anim.startsWith("singLEFT")) {
                    targetOffsetPos.set(-offsetIntensity, 0);
                } else if (anim.startsWith("singRIGHT")) {
                    targetOffsetPos.set(offsetIntensity, 0);
                } else if (anim.startsWith("singUP")) {
                    targetOffsetPos.set(0, -offsetIntensity);
                } else if (anim.startsWith("singDOWN")) {
                    targetOffsetPos.set(0, offsetIntensity);
                } else {
                    targetOffsetPos.set(0, 0);
                }
            }
        }

		// 2. คำนวณตำแหน่งพื้นฐาน (Base Scroll)
		if (deadzone == null)
		{
			target.getMidpoint(_point);
			_point.addPoint(targetOffset);
			_scrollTarget.set(_point.x - width * 0.5, _point.y - height * 0.5);
		}
		else
		{
			var edge:Float;
			var targetX:Float = target.x + targetOffset.x;
			var targetY:Float = target.y + targetOffset.y;

			if (style == SCREEN_BY_SCREEN)
			{
				if (targetX >= viewRight) _scrollTarget.x += viewWidth;
				else if (targetX + target.width < viewLeft) _scrollTarget.x -= viewWidth;

				if (targetY >= viewBottom) _scrollTarget.y += viewHeight;
				else if (targetY + target.height < viewTop) _scrollTarget.y -= viewHeight;
				
				bindScrollPos(_scrollTarget);
			}
			else
			{
				edge = targetX - deadzone.x;
				if (_scrollTarget.x > edge) _scrollTarget.x = edge;
				edge = targetX + target.width - deadzone.x - deadzone.width;
				if (_scrollTarget.x < edge) _scrollTarget.x = edge;

				edge = targetY - deadzone.y;
				if (_scrollTarget.y > edge) _scrollTarget.y = edge;
				edge = targetY + target.height - deadzone.y - deadzone.height;
				if (_scrollTarget.y < edge) _scrollTarget.y = edge;
			}

			if ((target is FlxSprite))
			{
				if (_lastTargetPosition == null) _lastTargetPosition = FlxPoint.get(target.x, target.y);
				_scrollTarget.x += (target.x - _lastTargetPosition.x) * followLead.x;
				_scrollTarget.y += (target.y - _lastTargetPosition.y) * followLead.y;

				_lastTargetPosition.x = target.x;
				_lastTargetPosition.y = target.y;
			}
		}

		// 3. คำนวณความนุ่มนวล (Lerp Calculations)
        
        // ทำให้ Offset ค่อยๆ ขยับ (Smooth Offset)
        var deltaMult:Float = elapsed / (1/60);
        currentOffsetPos.x += (targetOffsetPos.x - currentOffsetPos.x) * (offsetSmoothing * deltaMult);
        currentOffsetPos.y += (targetOffsetPos.y - currentOffsetPos.y) * (offsetSmoothing * deltaMult);

        // คำนวณความเร็วกล้องหลัก (Main Camera Speed)
		var mult:Float = 1 - Math.exp(-elapsed * followLerp / (1/60));
        
        // รวมตำแหน่ง Target หลัก + Offset แล้วค่อยเลื่อนกล้องไปหาจุดนั้น
		scroll.x += ((_scrollTarget.x + currentOffsetPos.x) - scroll.x) * mult;
		scroll.y += ((_scrollTarget.y + currentOffsetPos.y) - scroll.y) * mult;
	}

	public function setFilters(newShaders:Array<ShaderFilter>) {
		this.filters = cast newShaders;
	}
}