package mikolka.vslice.components;

import flixel.util.FlxStringUtil;
import flixel.FlxG;
import openfl.system.System as OpenFlSystem;
import mikolka.funkin.stats.FunkinStatsGraph;
import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFieldAutoSize;

/**
 * A debug overlay showing useful info.
 */
#if cpp
@:access(lime._internal.backend.native.NativeCFFI)
#end
class FunkinDebugDisplay extends Sprite
{
	static final UPDATE_DELAY:Int = 100;
	static final INNER_RECT_DIFF:Int = 3;
	static final OUTER_RECT_DIMENSIONS:Array<Int> = [234, 201];
	static final OTHERS_OFFSET:Int = 8;

	public var isAdvanced(default, set):Bool = false;
	public var backgroundOpacity(default, set):Float = 0.5;

	var currentFPS:Int;
	var deltaTimeout:Float;
	var times:Array<Float>;
	var color:Int;

	#if !html5
	var gcMem:Float;
	var gcMemPeak:Float;
	var taskMem:Float;
	var taskMemPeak:Float;
	#end

	var background:Shape;
	var fpsGraph:FunkinStatsGraph;
	var gcMemGraph:FunkinStatsGraph;
	var taskMemGraph:FunkinStatsGraph;

	// แยกตัวแปร Text ให้เหมือนกับการใช้ makeLuaText
	var fpsNumDisplay:TextField;
	var fpsTextDisplay:TextField;
	var memUsedDisplay:TextField;
	var memMaxDisplay:TextField;
	var engineDisplay:TextField;

	public function new(x:Float = 10, y:Float = 10, color:Int = 0x000000):Void
	{
		super();

		this.x = x;
		this.y = y;
		this.currentFPS = 0;
		this.deltaTimeout = 0.0;
		#if !html5
		this.gcMem = 0.0;
		this.gcMemPeak = 0.0;
		this.taskMem = 0.0;
		this.taskMemPeak = 0.0;
		#end
		this.times = [];
		this.color = color;
		this.backgroundOpacity = 0.6;
		this.isAdvanced = false;
	}

	function buildDebugDisplay(advanced:Bool):Void
	{
		removeChildren(0, numChildren);

		if (advanced) {
			final BG_WIDTH_MULTIPLIER:Float = #if html5 1 #else 1 #end;
			final BG_HEIGHT_MULTIPLIER:Float = #if html5 0.45 #else (MemoryUtil.supportsTaskMem()) ? 1 : 1 #end;

			background = new Shape();
			background.graphics.beginFill(0x3d3f41, 1);
			background.graphics.drawRect(0, 0, (OUTER_RECT_DIMENSIONS[0] * BG_WIDTH_MULTIPLIER) + (INNER_RECT_DIFF * 2),
				(OUTER_RECT_DIMENSIONS[1] * BG_HEIGHT_MULTIPLIER) + (INNER_RECT_DIFF * 2));
			background.graphics.endFill();
			background.graphics.beginFill(0x2c2f30, 1);
			background.graphics.drawRect(INNER_RECT_DIFF, INNER_RECT_DIFF, OUTER_RECT_DIMENSIONS[0] * BG_WIDTH_MULTIPLIER,
				OUTER_RECT_DIMENSIONS[1] * BG_HEIGHT_MULTIPLIER);
			background.graphics.endFill();
			background.alpha = backgroundOpacity;
			addChild(background);
		} else {
			background = new Shape();
			background.alpha = 0; 
			addChild(background);
		}

		if (advanced)
		{
			createAdvancedElements();
			updateAdvancedDisplay();
		}
		else
		{
			createSimpleElements();
			updateSimpleDisplay();
		}
	}

	function createAdvancedElements():Void
	{
		final graphsWidth:Int = OUTER_RECT_DIMENSIONS[0] + (INNER_RECT_DIFF * 2) - (OTHERS_OFFSET * 3);
		final graphsHeight:Int = 25;

		fpsGraph = new FunkinStatsGraph(OTHERS_OFFSET, OTHERS_OFFSET + 49, graphsWidth, graphsHeight, color);
		fpsGraph.textDisplay.y = -49;
		fpsGraph.minValue = 0;
		addChild(fpsGraph);

		#if !html5
		gcMemGraph = new FunkinStatsGraph(OTHERS_OFFSET, Math.floor(OTHERS_OFFSET + (fpsGraph.y + fpsGraph.axisHeight) + 22), graphsWidth, graphsHeight, color);
		gcMemGraph.minValue = 0;
		addChild(gcMemGraph);

		if (MemoryUtil.supportsTaskMem())
		{
			taskMemGraph = new FunkinStatsGraph(OTHERS_OFFSET, Math.floor(OTHERS_OFFSET + (gcMemGraph.y + gcMemGraph.axisHeight) + 22), graphsWidth,
				graphsHeight, color);
			taskMemGraph.minValue = 0;
			addChild(taskMemGraph);
		}
		#end
	}

	function createSimpleElements():Void
	{
		// 1. ตัวเลข FPS (Size 30)
		fpsNumDisplay = new TextField();
		fpsNumDisplay.x = 10;
		fpsNumDisplay.y = 9;
		fpsNumDisplay.selectable = false;
		fpsNumDisplay.mouseEnabled = false;
		fpsNumDisplay.defaultTextFormat = new TextFormat('consola.ttf', 30, color);
		fpsNumDisplay.autoSize = TextFieldAutoSize.LEFT;
		addChild(fpsNumDisplay);

		// 2. ข้อความ "FPS" (Size 14)
		fpsTextDisplay = new TextField();
		fpsTextDisplay.x = 50;
		fpsTextDisplay.y = 21;
		fpsTextDisplay.selectable = false;
		fpsTextDisplay.mouseEnabled = false;
		fpsTextDisplay.defaultTextFormat = new TextFormat('consola.ttf', 14, color);
		fpsTextDisplay.text = "FPS";
		fpsTextDisplay.autoSize = TextFieldAutoSize.LEFT;
		addChild(fpsTextDisplay);

		// 3. ปริมาณ Memory ที่ใช้ (Size 14)
		memUsedDisplay = new TextField();
		memUsedDisplay.x = 12;
		memUsedDisplay.y = 41;
		memUsedDisplay.selectable = false;
		memUsedDisplay.mouseEnabled = false;
		memUsedDisplay.defaultTextFormat = new TextFormat('consola.ttf', 14, color);
		memUsedDisplay.autoSize = TextFieldAutoSize.LEFT;
		addChild(memUsedDisplay);

		// 4. ปริมาณ Memory สูงสุด (Size 14, Alpha 0.6)
		memMaxDisplay = new TextField();
		memMaxDisplay.x = 87;
		memMaxDisplay.y = 42;
		memMaxDisplay.selectable = false;
		memMaxDisplay.mouseEnabled = false;
		memMaxDisplay.defaultTextFormat = new TextFormat('consola.ttf', 14, color);
		memMaxDisplay.alpha = 0.6;
		memMaxDisplay.autoSize = TextFieldAutoSize.LEFT;
		addChild(memMaxDisplay);

		// 5. ชื่อ Engine (Size 14)
		engineDisplay = new TextField();
		engineDisplay.x = 12;
		engineDisplay.y = 60;
		engineDisplay.selectable = false;
		engineDisplay.mouseEnabled = false;
		engineDisplay.defaultTextFormat = new TextFormat('consola.ttf', 14, color);
		engineDisplay.text = "Lostbloom Rewire";
		engineDisplay.autoSize = TextFieldAutoSize.LEFT;
		addChild(engineDisplay);
	}

	override function __enterFrame(deltaTime:Int):Void
	{
		if(!visible) return;
		#if html5
		final currentTime:Float = js.Browser.window.performance.now();
		#else
		final currentTime:Float = haxe.Timer.stamp() * 1000;
		#end

		times.push(currentTime);

		while (times[0] < currentTime - 1000)
		{
			times.shift();
		}

		if (deltaTimeout < UPDATE_DELAY)
		{
			deltaTimeout += deltaTime;
			return;
		}

		currentFPS = times.length;

		#if !html5
		gcMem = MemoryUtil.getGCMemory();

		if (gcMem > gcMemPeak)
			gcMemPeak = gcMem;

		if (MemoryUtil.supportsTaskMem())
		{
			taskMem = MemoryUtil.getTaskMemory();

			if (taskMem > taskMemPeak)
				taskMemPeak = taskMem;
		}
		#end

		if (isAdvanced)
		{
			updateAdvancedDisplay();
		}
		else
		{
			updateSimpleDisplay();
		}

		deltaTimeout = 0.0;
	}

	function updateAdvancedDisplay():Void
	{
		updateFPSGraph();
		#if !html5
		updateGcMemGraph();
		updateTaskMemGraph();
		#end

		final info:Array<String> = [];
		info.push('FPS: $currentFPS');
		info.push('AVG FPS: ${Math.floor(fpsGraph.average())}');
		info.push('1% LOW FPS: ${Math.floor(fpsGraph.lowest())}');
		fpsGraph.textDisplay.text = info.join('\n');

		#if !html5
		gcMemGraph.textDisplay.text = 'GC MEM: ${FlxStringUtil.formatBytes(gcMem).toLowerCase()} / ${FlxStringUtil.formatBytes(gcMemPeak).toLowerCase()}';

		if (taskMemGraph != null)
		{
			taskMemGraph.textDisplay.text = 'TASK MEM: ${FlxStringUtil.formatBytes(taskMem).toLowerCase()} / ${FlxStringUtil.formatBytes(taskMemPeak).toLowerCase()}';
		}
		#end
	}

	function updateSimpleDisplay():Void
	{
		if (fpsNumDisplay != null)
		{
			var memoryMax:Float = OpenFlSystem.totalMemory;

			// อัปเดตข้อความต่างๆ แบบแยกชิ้น
			fpsNumDisplay.text = Std.string(currentFPS);
			memUsedDisplay.text = FlxStringUtil.formatBytes(gcMem);
			memMaxDisplay.text = "/ " + FlxStringUtil.formatBytes(memoryMax);

			// เลื่อนตำแหน่งแกน X ให้สัมพันธ์กับความกว้างของข้อความ (เหมือน getTextWidth ใน Lua)
			fpsTextDisplay.x = fpsNumDisplay.x + fpsNumDisplay.textWidth + 3;
			memMaxDisplay.x = memUsedDisplay.x + memUsedDisplay.textWidth + 3;

			// เปลี่ยนสีตัวเลข FPS ถ้าเฟรมเรตตก
			var curColor:Int = 0xFFFFFF; // สีขาว
			if (currentFPS < FlxG.drawFramerate * 0.5)
				curColor = 0xFF0000; // สีแดง

			fpsNumDisplay.textColor = curColor;
			fpsTextDisplay.textColor = curColor;
		}
	}

	function updateFPSGraph(?currentFPS:Int = 0):Void
	{
		fpsGraph.maxValue = FlxG.drawFramerate;
		fpsGraph.update(times.length);
	}

	#if !html5
	function updateGcMemGraph(?currentFPS:Int = 0):Void
	{
		gcMemGraph.maxValue = gcMemPeak;
		gcMemGraph.update(gcMem);
	}

	function updateTaskMemGraph(?currentFPS:Int = 0):Void
	{
		if (taskMemGraph != null)
		{
			taskMemGraph.maxValue = taskMemPeak;
			taskMemGraph.update(taskMem);
		}
	}
	#end

	function set_isAdvanced(value:Bool):Bool
	{
		buildDebugDisplay(value);
		return isAdvanced = value;
	}

	function set_backgroundOpacity(value:Float):Float
	{
		if (background != null && isAdvanced)
			background.alpha = value;
		else if (background != null && !isAdvanced)
			background.alpha = 0;

		return backgroundOpacity = value;
	}
}