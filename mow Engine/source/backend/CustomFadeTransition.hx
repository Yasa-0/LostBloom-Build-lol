package backend;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxSubState;
import flixel.util.FlxColor;
import flixel.addons.display.FlxRuntimeShader; // เรียกใช้ RuntimeShader สำหรับ PE 1.0.4+

class CustomFadeTransition extends FlxSubState {
	public static var finishCallback:Void->Void;
	var isTransIn:Bool = false;
	var transSprite:FlxSprite;
	var sideShader:FlxRuntimeShader;

	var duration:Float;
	var curTime:Float = 0;

	public function new(duration:Float, isTransIn:Bool)
	{
		this.duration = duration;
		this.isTransIn = isTransIn;
		super();
	}

	override function create()
	{
		cameras = [FlxG.cameras.list[FlxG.cameras.list.length-1]];
		var width:Int = Std.int(FlxG.width / Math.max(camera.zoom, 0.001));
		var height:Int = Std.int(FlxG.height / Math.max(camera.zoom, 0.001));

		transSprite = new FlxSprite().makeGraphic(width, height, FlxColor.BLACK);
		transSprite.scrollFactor.set();
		transSprite.screenCenter();
		
		// เขียน Fragment Shader ลงตัวแปร String แทนเพื่อเลี่ยงบั๊ก OpenFL Macro
		var fragCode:String = "
			#pragma header
			
			uniform float progression;
			uniform float alphaScale;
			uniform vec2 res;

			void main() {
				float transitionSideDiamondPixelSize = 48.0 * alphaScale;
				
				vec2 screenCoord = openfl_TextureCoordv.xy * res;
				vec2 flippedUv = openfl_TextureCoordv.xy;
				flippedUv.x = 1.0 - flippedUv.x;
				
				float xFraction = fract(screenCoord.x / transitionSideDiamondPixelSize);
				float yFraction = fract(screenCoord.y / transitionSideDiamondPixelSize);
				
				float xDistance = abs(xFraction - 0.5);
				float yDistance = abs(yFraction - 0.5);
				
				if (xDistance + yDistance + flippedUv.x + flippedUv.y < progression * 4.0) {
					gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
				} else {
					gl_FragColor = vec4(0.0, 0.0, 0.0, 0.0);
				}
			}
		";

		// กำหนดค่าและสร้าง RuntimeShader
		sideShader = new FlxRuntimeShader(fragCode);
		sideShader.setFloat('alphaScale', 1.0);
		sideShader.setFloatArray('res', [width, height]);
		
		if (isTransIn) {
			sideShader.setFloat('progression', 1.0); 
		} else {
			sideShader.setFloat('progression', 0.0);
		}

		transSprite.shader = sideShader;
		add(transSprite);
		super.create();
	}

	override function update(elapsed:Float) {
		super.update(elapsed);

		if (duration <= 0) {
			close();
			return;
		}

		curTime += elapsed;
		var percent:Float = curTime / duration;
		if (percent > 1.0) percent = 1.0;

		// ใช้ setFloat เพื่ออัปเดตค่า progression ลงไปในตัว Shader แบบ Real-time
		if (isTransIn) {
			sideShader.setFloat('progression', 1.0 - percent);
		} else {
			sideShader.setFloat('progression', percent);
		}

		if(curTime >= duration)
		{
			close();
		}
	}

	// Don't delete this
	override function close():Void
	{
		super.close();

		if(finishCallback != null)
		{
			finishCallback();
			finishCallback = null;
		}
	}
}