package mikolka.vslice.components.crash;

import mikolka.compatibility.VsliceOptions;
import mikolka.compatibility.ModsHelper;
import mikolka.vslice.ui.title.TitleState;
import mikolka.vslice.ui.MainMenuState;
import flixel.FlxBasic;
import haxe.CallStack.StackItem;

class UserErrorSubstate extends MusicBeatSubstate
{
	var error:CrashData;
	var isCritical:Bool;
	var allowClosing:Bool = false;
	var camOverlay:FlxCamera;
	var previousMouseVisible:Bool = true;
	var previousMouseEnabled:Bool = true;

	var restartX:Float = 0;
	var restartY:Float = 0;
	var restartW:Float = 0;
	var restartH:Float = 0;
	var quitX:Float = 0;
	var quitY:Float = 0;
	var quitW:Float = 0;
	var quitH:Float = 0;

	// Scroll state for long crash messages and call stacks.
	var stackPanelX:Float = 0;
	var stackPanelY:Float = 0;
	var stackPanelW:Float = 0;
	var stackPanelH:Float = 0;
	var stackRowsY:Float = 0;
	var stackRowH:Float = 25;
	var stackVisibleRows:Int = 1;
	var stackScrollOffset:Int = 0;
	var stackRenderObjects:Array<FlxBasic> = [];

	var messageHitX:Float = 0;
	var messageHitY:Float = 0;
	var messageHitW:Float = 0;
	var messageHitH:Float = 0;
	var messageTextX:Float = 0;
	var messageTextY:Float = 0;
	var messageTextW:Float = 0;
	var messageVisibleLines:Int = 2;
	var messageScrollOffset:Int = 0;
	var errorMessageLines:Array<String> = [];
	var messageRenderObjects:Array<FlxBasic> = [];

	public static function makeMessage(errorMessage:String, description:String)
	{
		var state = FlxG.state;
		while (state.subState != null)
			state = state.subState;
		state.persistentUpdate = false;
		state.openSubState(new UserErrorSubstate(UserErrorSubstate.collectMessageData(errorMessage, description)));
	}

	public static function makeError(error:CrashData, isCritical:Bool = false)
	{
		var state = FlxG.state;
		while (state.subState != null)
			state = state.subState;
		state.persistentUpdate = false;
		state.openSubState(new UserErrorSubstate(error, isCritical));
	}

	public function new(error:CrashData, isCritical:Bool = false)
	{
		this.error = error;
		this.isCritical = isCritical;
		camOverlay = new FlxCamera();
		camOverlay.bgColor = FlxColor.TRANSPARENT;
		FlxG.cameras.add(camOverlay);
		super();
	}

	override function create()
	{
		super.create();
		_parentState.persistentUpdate = false;
		// Crash report UI must receive mouse clicks even if the game disabled mouse input.
		previousMouseVisible = FlxG.mouse.visible;
		previousMouseEnabled = FlxG.mouse.enabled;
		FlxG.mouse.enabled = true;
		FlxG.mouse.visible = true;
		drawCrashReport(error);
	}

	function panel(x:Float, y:Float, w:Float, h:Float, color:FlxColor, ?borderColor:FlxColor):FlxSprite
	{
		var s = new FlxSprite(x, y);
		s.makeGraphic(Std.int(Math.max(1, w)), Std.int(Math.max(1, h)), color);
		s.camera = camOverlay;
		add(s);
		if (borderColor != null)
		{
			var border = new FlxSprite(x, y);
			border.makeGraphic(Std.int(Math.max(1, w)), 1, borderColor);
			border.camera = camOverlay;
			add(border);
			border = new FlxSprite(x, y + h - 1);
			border.makeGraphic(Std.int(Math.max(1, w)), 1, borderColor);
			border.camera = camOverlay;
			add(border);
			border = new FlxSprite(x, y);
			border.makeGraphic(1, Std.int(Math.max(1, h)), borderColor);
			border.camera = camOverlay;
			add(border);
			border = new FlxSprite(x + w - 1, y);
			border.makeGraphic(1, Std.int(Math.max(1, h)), borderColor);
			border.camera = camOverlay;
			add(border);
		}
		return s;
	}

	function label(value:String, x:Float, y:Float, w:Float, size:Int, color:FlxColor, ?align:FlxTextAlign = LEFT):FlxText
	{
		var t = new FlxText(x, y, w, value);
		t.setFormat(Paths.font('vcr.ttf'), size, color, align);
		t.antialiasing = true;
		t.camera = camOverlay;
		add(t);
		return t;
	}

	/**
	 * Loads a PNG from assets/images/crash/icons and draws it on the crash overlay.
	 * The crash icon pack supplied with this file uses these exact asset names.
	 */
	function addCrashIcon(name:String, x:Float, y:Float, size:Int):FlxSprite
	{
		var spr = new FlxSprite(x, y);
		spr.loadGraphic(Paths.image('crash/icons/' + name));
		spr.setGraphicSize(size, size);
		spr.updateHitbox();
		spr.antialiasing = true;
		spr.camera = camOverlay;
		add(spr);
		return spr;
	}

	function clearTrackedObjects(objects:Array<FlxBasic>):Void
	{
		for (obj in objects)
		{
			remove(obj, true);
			obj.destroy();
		}
		objects.splice(0, objects.length);
	}

	function wrapMessage(text:String, maxChars:Int):Array<String>
	{
		var result:Array<String> = [];
		if (text == null)
			text = "Unknown error";
		maxChars = Std.int(Math.max(12, maxChars));

		for (paragraph in text.split("\n"))
		{
			var rest = paragraph;
			if (rest.length == 0)
			{
				result.push("");
				continue;
			}

			while (rest.length > maxChars)
			{
				var splitAt = rest.lastIndexOf(" ", maxChars);
				if (splitAt <= 0)
					splitAt = maxChars;
				result.push(rest.substr(0, splitAt));
				rest = rest.substr(splitAt);
				while (rest.length > 0 && rest.charAt(0) == " ")
					rest = rest.substr(1);
			}
			result.push(rest);
		}

		if (result.length == 0)
			result.push("Unknown error");
		return result;
	}

	function renderErrorMessage():Void
	{
		clearTrackedObjects(messageRenderObjects);
		var remaining = errorMessageLines.length - messageScrollOffset;
		var visible = Std.int(Math.min(messageVisibleLines, Math.max(0, remaining)));
		for (i in 0...visible)
		{
			var line = errorMessageLines[messageScrollOffset + i];
			var lineY = messageTextY + i * 14;
			var text = label(line, messageTextX, lineY, messageTextW, 12, FlxColor.fromRGB(255, 107, 117));
			messageRenderObjects.push(text);
		}

		if (errorMessageLines.length > messageVisibleLines)
		{
			var hint = label("WHEEL TO SCROLL", messageHitX + messageHitW - 106, messageHitY + messageHitH - 11, 94, 8, FlxColor.fromRGB(255, 145, 152), RIGHT);
			messageRenderObjects.push(hint);
		}
	}

	function renderStackRows(data:CrashData):Void
	{
		clearTrackedObjects(stackRenderObjects);
		var rows:Int = data.trace == null ? 0 : data.trace.length;
		var maxScroll = Std.int(Math.max(0, rows - stackVisibleRows));
		stackScrollOffset = Std.int(Math.max(0, Math.min(maxScroll, stackScrollOffset)));
		var shown = Std.int(Math.min(stackVisibleRows, Math.max(0, rows - stackScrollOffset)));

		for (i in 0...shown)
		{
			var rowIndex = stackScrollOffset + i;
			var row = data.trace[rowIndex];
			var ry = stackRowsY + i * stackRowH;
			if (rowIndex == 0)
			{
				stackRenderObjects.push(panel(stackPanelX + 10, ry, stackPanelW - 20, stackRowH, FlxColor.fromRGB(17, 54, 64, 255)));
			}
			else if (rowIndex % 2 == 0)
			{
				stackRenderObjects.push(panel(stackPanelX + 10, ry, stackPanelW - 20, stackRowH, FlxColor.fromRGB(22, 30, 40, 255)));
			}

			var functionName = row.length > 0 ? row[0] : "(unknown)";
			var lineNo = row.length > 1 ? row[row.length - 1] : "";
			if (row.length == 2 && lineNo.indexOf("Line:") == 0)
				lineNo = lineNo.substr(5);

			var maxFunctionWidth = Std.int(Math.max(10, stackPanelW * 0.49));
			if (functionName.length > 46)
				functionName = functionName.substr(0, 43) + "...";

			stackRenderObjects.push(label(Std.string(rowIndex + 1), stackPanelX + 20, ry + 5, 28, 12,
				rowIndex == 0 ? FlxColor.CYAN : FlxColor.fromRGB(177, 194, 213)));
			stackRenderObjects.push(label(functionName, stackPanelX + 60, ry + 5, maxFunctionWidth, 12, FlxColor.fromRGB(220, 231, 243)));
			stackRenderObjects.push(label(lineNo.replace("Line:", ""), stackPanelX + stackPanelW - 78, ry + 5, 54, 12,
				rowIndex == 0 ? FlxColor.CYAN : FlxColor.fromRGB(220, 231, 243), RIGHT));
		}

		var status:String;
		if (rows == 0)
			status = "No stack entries";
		else
		{
			var first = stackScrollOffset + 1;
			var last = stackScrollOffset + shown;
			status = 'Entries $first-$last of $rows  |  Wheel scroll / PgUp / PgDn';
		}
		stackRenderObjects.push(label(status, stackPanelX + 18, stackPanelY + stackPanelH - 21,
			stackPanelW - 36, 10, FlxColor.fromRGB(143, 165, 187)));
	}

	function setStackScroll(nextOffset:Int):Void
	{
		var rows = error.trace == null ? 0 : error.trace.length;
		var maxScroll = Std.int(Math.max(0, rows - stackVisibleRows));
		var next = Std.int(Math.max(0, Math.min(maxScroll, nextOffset)));
		if (next != stackScrollOffset)
		{
			stackScrollOffset = next;
			renderStackRows(error);
		}
	}

	function setMessageScroll(nextOffset:Int):Void
	{
		var maxScroll = Std.int(Math.max(0, errorMessageLines.length - messageVisibleLines));
		var next = Std.int(Math.max(0, Math.min(maxScroll, nextOffset)));
		if (next != messageScrollOffset)
		{
			messageScrollOffset = next;
			renderErrorMessage();
		}
	}

	function drawCrashReport(data:CrashData):Void
	{
		var sw:Float = FlxG.width;
		var sh:Float = FlxG.height;
		var pad:Float = Math.max(14, sw * 0.018);
		var headerH:Float = Math.max(54, sh * 0.075);
		var footerH:Float = Math.max(66, sh * 0.095);
		var gap:Float = 14;
		var bodyY:Float = headerH + 12;
		var bodyH:Float = sh - bodyY - footerH - 22;
		var rightW:Float = Math.max(230, sw * 0.30);
		var leftW:Float = sw - pad * 2 - gap - rightW;
		var leftX:Float = pad;
		var rightX:Float = leftX + leftW + gap;
		var star = #if (CHECK_FOR_UPDATES || debug) "" #else "*" #end;

		panel(0, 0, sw, sh, FlxColor.fromRGB(8, 12, 18, 248));
		panel(0, 0, sw, headerH, FlxColor.fromRGB(14, 20, 29, 255), FlxColor.fromRGB(42, 57, 72));

		// Brand: use the Mow Engine PNG logo instead of a text placeholder like [M].
		var logoSize:Int = 32;
		addCrashIcon("mow_engine_logo", pad, (headerH - logoSize) / 2, logoSize);
		label("MOW ENGINE", pad + 42, 12, 145, 21, FlxColor.fromRGB(75, 229, 240));
		label('${MainMenuState.MowVersion}$star  |  FRIDAY NIGHT FUNKIN\' MOD ENGINE', pad + 194, 19, sw * 0.47, 14, FlxColor.fromRGB(170, 190, 210));

		var crashBadgeX = sw - pad - 166;
		panel(crashBadgeX, 12, 166, 32, FlxColor.fromRGB(52, 22, 29), FlxColor.fromRGB(255, 91, 103));
		addCrashIcon("warning", crashBadgeX + 8, 18, 20);
		label("CRASH REPORT", crashBadgeX + 34, 20, 124, 14, FlxColor.fromRGB(255, 105, 115), CENTER);

		// Main error summary
		var summaryH:Float = Math.max(150, bodyH * 0.31);
		panel(leftX, bodyY, leftW, summaryH, FlxColor.fromRGB(17, 25, 35, 255), FlxColor.fromRGB(40, 55, 70));
		addCrashIcon("warning", leftX + 20, bodyY + 23, 64);
		label("Something went wrong", leftX + 100, bodyY + 20, leftW - 120, 28, FlxColor.fromRGB(240, 246, 252));
		label("The game encountered an unexpected runtime error.", leftX + 100, bodyY + 58, leftW - 120, 15, FlxColor.fromRGB(159, 180, 202));
		var errH:Float = 54;
		var errY = bodyY + summaryH - errH - 12;
		panel(leftX + 14, errY, leftW - 28, errH, FlxColor.fromRGB(34, 22, 29, 255), FlxColor.fromRGB(104, 42, 52));
		// Keep the field label on one line. The message starts in its own column,
		// so a long error wraps below itself rather than below the word ERROR.
		label("ERROR", leftX + 26, errY + 11, 50, 13, FlxColor.fromRGB(255, 107, 117));
		messageHitX = leftX + 14;
		messageHitY = errY;
		messageHitW = leftW - 28;
		messageHitH = errH;
		messageTextX = leftX + 84;
		messageTextY = errY + 10;
		messageTextW = Math.max(24, messageHitX + messageHitW - 12 - messageTextX);
		messageVisibleLines = 2;
		errorMessageLines = wrapMessage(data.message, Std.int(messageTextW / 7));
		messageScrollOffset = 0;
		renderErrorMessage();

		// Call stack panel
		var stackY = bodyY + summaryH + gap;
		var stackH = bodyH - summaryH - gap;
		panel(leftX, stackY, leftW, stackH, FlxColor.fromRGB(15, 22, 31, 255), FlxColor.fromRGB(40, 55, 70));
		label("=  CALL STACK", leftX + 18, stackY + 12, leftW - 36, 18, FlxColor.fromRGB(220, 233, 246));
		var tableY = stackY + 42;
		panel(leftX + 10, tableY, leftW - 20, 27, FlxColor.fromRGB(25, 36, 48, 255));
		label("#", leftX + 20, tableY + 6, 28, 12, FlxColor.fromRGB(142, 164, 187));
		label("FUNCTION", leftX + 60, tableY + 6, leftW * 0.49, 12, FlxColor.fromRGB(142, 164, 187));
		label("LINE", leftX + leftW - 78, tableY + 6, 54, 12, FlxColor.fromRGB(142, 164, 187), RIGHT);
		stackPanelX = leftX;
		stackPanelY = stackY;
		stackPanelW = leftW;
		stackPanelH = stackH;
		stackRowH = 25;
		stackRowsY = tableY + 28;
		stackVisibleRows = Std.int(Math.max(1, Math.floor((stackH - 105) / stackRowH)));
		stackScrollOffset = 0;
		renderStackRows(data);

		// Runtime panel
		panel(rightX, bodyY, rightW, bodyH, FlxColor.fromRGB(15, 22, 31, 255), FlxColor.fromRGB(40, 55, 70));
		addCrashIcon("info", rightX + 17, bodyY + 12, 24);
		label("RUNTIME INFO", rightX + 49, bodyY + 16, rightW - 65, 17, FlxColor.fromRGB(220, 233, 246));
		var dateParts = data.date.split(" ");
		var timeValue = dateParts.length > 1 ? dateParts[1] : "--:--:--";
		var dateValue = dateParts.length > 0 ? dateParts[0] : "Unknown";
		var infoY = bodyY + 56;
		var infoGap = Math.max(36, Math.min(48, bodyH * 0.09));
		var infoLabels = ["MOD", "ENGINE", "SYSTEM", "DATE", "TIME"];
		var infoIcons = ["folder", "cpu", "monitor", "calendar", "clock"];
		var infoValues = [data.activeMod, "Mow Engine " + MainMenuState.MowVersion, data.systemName, dateValue, timeValue];
		for (i in 0...infoLabels.length)
		{
			var iy = infoY + i * infoGap;
			panel(rightX + 16, iy + infoGap - 1, rightW - 32, 1, FlxColor.fromRGB(39, 52, 66));
			addCrashIcon(infoIcons[i], rightX + 18, iy + (infoGap - 24) / 2, 24);
			// Center every row's icon, label, and value on the same vertical axis.
			var labelSize:Int = 12;
			var valueSize:Int = 13;
			var labelY:Float = iy + (infoGap - labelSize) / 2;
			var valueY:Float = iy + (infoGap - valueSize) / 2;
			label(infoLabels[i], rightX + 49, labelY, rightW * 0.20, labelSize, FlxColor.fromRGB(143, 169, 195));
			var val:String = infoValues[i] == null ? "Unknown" : infoValues[i];
			var valueX:Float = rightX + rightW * 0.43;
			var valueWidth:Float = rightW * 0.52;
			// Keep a small gap between the field name and the value on narrow windows.
			valueWidth = Math.max(24, Math.min(valueWidth, rightX + rightW - 18 - valueX));
			var maxVal:Int = Std.int(Math.max(8, valueWidth / 7));
			if (val.length > maxVal) val = val.substr(0, maxVal - 3) + "...";
			label(val, valueX, valueY, valueWidth, valueSize, FlxColor.fromRGB(224, 235, 246));
		}
		var detailY = infoY + infoGap * 5 + 12;
		if (detailY < bodyY + bodyH - 44)
		{
			panel(rightX + 16, detailY, rightW - 32, Math.max(32, bodyY + bodyH - detailY - 18), FlxColor.fromRGB(12, 18, 26, 255), FlxColor.fromRGB(39, 52, 66));
			label("DETAILS", rightX + 28, detailY + 10, rightW - 56, 13, FlxColor.fromRGB(143, 169, 195));
			label(getLogger(), rightX + 28, detailY + 34, rightW - 56, 11, FlxColor.fromRGB(188, 204, 220));
			if (isCritical)
				label("REPORT: github.com/Psych-Slice/P-Slice", rightX + 28, detailY + 54, rightW - 56, 10, FlxColor.fromRGB(75, 210, 225));
		}

		// Footer and actions
		var footerY = sh - footerH;
		panel(0, footerY, sw, footerH, FlxColor.fromRGB(13, 19, 27, 255), FlxColor.fromRGB(40, 55, 70));
		label("Mow Engine  •  Crash diagnostics", pad, footerY + 24, sw * 0.36, 12, FlxColor.fromRGB(145, 166, 190));
		restartW = Math.min(190, sw * 0.20);
		restartH = 42;
		restartX = sw - pad - restartW - 130;
		restartY = footerY + (footerH - restartH) / 2;
		quitW = 112;
		quitH = restartH;
		quitX = sw - pad - quitW;
		quitY = restartY;
		panel(restartX, restartY, restartW, restartH, FlxColor.fromRGB(21, 218, 231, 255), FlxColor.fromRGB(78, 245, 249));
		label(isCritical ? "RESTART" : "CONTINUE", restartX + 4, restartY + 12, restartW - 8, 15, FlxColor.fromRGB(5, 22, 28), CENTER);
		panel(quitX, quitY, quitW, quitH, FlxColor.fromRGB(17, 24, 34, 255), FlxColor.fromRGB(104, 126, 150));
		label("QUIT", quitX + 4, quitY + 12, quitW - 8, 14, FlxColor.fromRGB(220, 232, 245), CENTER);
	}

	public static function collectErrorData(errorMessage:String, callStack:Array<StackItem>):CrashData
	{
		var errMsg = new Array<Array<String>>();
		var errExtended = new Array<String>();
		for (stackItem in callStack)
		{
			switch (stackItem)
			{
				case FilePos(s, file, pos_line, column):
					var line = new Array<String>();
					switch (s)
					{
						case Module(m):
							line.push("MD:" + m);
						case CFunction:
							line.push("Native function");
						case Method(classname, method):
							var regex = ~/(([A-Z]+[A-z]*)\.?)+/g;
							regex.match(classname);
							line.push("CLS:" + regex.matched(0) + ":" + method + "()");
						default:
							#if sys Sys.println #else trace #end (stackItem);
					}
					line.push("Line:" + pos_line);
					errMsg.push(line);
					errExtended.push('In file ${file}: ${line.join("  ")}');
				default:
					#if sys Sys.println #else trace #end (stackItem);
			}
		}
		return {
			logToFile: true,
			message: errorMessage,
			trace: errMsg,
			extendedTrace: errExtended,
			date: Date.now().toString(),
			systemName: getPlatform(),
			activeMod: ModsHelper.getActiveMod()
		}
	}

	public static function collectMessageData(errorMessage:String, description:String):CrashData
	{
		var tbl = new Array<Array<String>>();
		for (x in description.split("\n"))
		{
			tbl.push([x]);
		}
		return {
			logToFile: false,
			extendedTrace: [],
			trace: tbl,
			message: errorMessage,
			date: Date.now().toString(),
			systemName: getPlatform(),
			activeMod: ModsHelper.getActiveMod()
		};
	}

	public inline static function getPlatform():String
	{
		return #if android
			'Android'
		#elseif linux
			'Linux'
		#elseif mac
			'macOS'
		#elseif ios
			'iOS'
		#elseif windows
			'Windows'
		#elseif html5
			FlxG.html5.platform.getName() + '(${FlxG.html5.browser.getName()})'
		#else
			'Unknown'
		#end;
	}
    public inline static function getLogger():String
        {
            return switch(VsliceOptions.LOGGING){
                case "File": "Logs available in the 'latest.log' file";
                case "Console": "Check the console for logs";
                case "None": "Logs disabled!";
                default: "Is the logger corrupted???";
            }
        }


	inline function pointerInside(x:Float, y:Float, w:Float, h:Float):Bool
	{
		// Convert the pointer to the overlay camera's coordinate space. Raw screenX/Y
		// can be in a different coordinate space when the game is scaled or zoomed.
		var mousePos = FlxG.mouse.getScreenPosition(camOverlay);
		var inside = mousePos.x >= x && mousePos.x <= x + w && mousePos.y >= y && mousePos.y <= y + h;
		mousePos.put();
		return inside;
	}

	override function destroy()
	{
		// Remove the dedicated overlay camera and restore the cursor state when the report closes.
		if (camOverlay != null)
			FlxG.cameras.remove(camOverlay);
		FlxG.mouse.visible = previousMouseVisible;
		FlxG.mouse.enabled = previousMouseEnabled;
		super.destroy();
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		if (!allowClosing)
		{
			// Let the first frame finish drawing before accepting any input.
			allowClosing = true;
			return;
		}

		// Scroll long call stacks with the wheel while the pointer is over the stack panel.
		// The error message banner has its own independent scroll position.
		var pointerOnStack = pointerInside(stackPanelX, stackPanelY, stackPanelW, stackPanelH);
		var pointerOnMessage = pointerInside(messageHitX, messageHitY, messageHitW, messageHitH);
		var wheel:Int = FlxG.mouse.wheel;
		if (wheel != 0 && pointerOnStack)
		{
			setStackScroll(stackScrollOffset - wheel);
			return;
		}
		if (wheel != 0 && pointerOnMessage && errorMessageLines.length > messageVisibleLines)
		{
			setMessageScroll(messageScrollOffset - wheel);
			return;
		}

		if (pointerOnStack)
		{
			if (FlxG.keys.justPressed.PAGEDOWN || FlxG.keys.justPressed.DOWN)
			{
				setStackScroll(stackScrollOffset + (FlxG.keys.justPressed.PAGEDOWN ? stackVisibleRows : 1));
				return;
			}
			if (FlxG.keys.justPressed.PAGEUP || FlxG.keys.justPressed.UP)
			{
				setStackScroll(stackScrollOffset - (FlxG.keys.justPressed.PAGEUP ? stackVisibleRows : 1));
				return;
			}
		}
		if (pointerOnMessage && errorMessageLines.length > messageVisibleLines)
		{
			if (FlxG.keys.justPressed.PAGEDOWN || FlxG.keys.justPressed.DOWN)
			{
				setMessageScroll(messageScrollOffset + (FlxG.keys.justPressed.PAGEDOWN ? messageVisibleLines : 1));
				return;
			}
			if (FlxG.keys.justPressed.PAGEUP || FlxG.keys.justPressed.UP)
			{
				setMessageScroll(messageScrollOffset - (FlxG.keys.justPressed.PAGEUP ? messageVisibleLines : 1));
				return;
			}
		}

		var mousePressed:Bool = FlxG.mouse.justPressed;
		var mouseOnRestart:Bool = mousePressed && pointerInside(restartX, restartY, restartW, restartH);
		var mouseOnQuit:Bool = mousePressed && pointerInside(quitX, quitY, quitW, quitH);

		if (controls.ACCEPT || TouchUtil.justPressed || mouseOnRestart)
		{
			if (!isCritical)
			{
				_parentState.persistentUpdate = true;
				close();
				return;
			}

			TitleState.initialized = false;
			if (ScreenshotPlugin.instance != null)
			{
				ScreenshotPlugin.instance.destroy();
				ScreenshotPlugin.instance = null;
			}
			TitleState.closedState = false;
			#if LEGACY_PSYCH
			if (Main.debugDisplay != null)
				Main.debugDisplay.visible = ClientPrefs.showFPS;
			#else
			if (Main.debugDisplay != null)
				Main.debugDisplay.visible = ClientPrefs.data.showFPS;
			#end
			FlxG.sound.pause();
			FlxTween.globalManager.clear();
			FlxG.resetGame();
			return;
		}

		else if (mouseOnQuit || (controls.BACK && isCritical))
		{
			#if sys
			// The visible QUIT button works for both critical and non-critical reports.
			Sys.exit(1);
			#else
			if (!isCritical && mouseOnQuit)
			{
				_parentState.persistentUpdate = true;
				close();
			}
			#end
		}
	}

}

typedef CrashData =
{
	logToFile:Bool,
	message:String,
	trace:Array<Array<String>>,
	extendedTrace:Array<String>,
	date:String,
	systemName:String,
	activeMod:String
}
