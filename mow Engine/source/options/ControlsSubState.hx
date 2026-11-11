package options;

import backend.InputFormatter;
import backend.Language;
import backend.ClientPrefs;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.math.FlxMath;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.input.keyboard.FlxKey;
import flixel.input.gamepad.FlxGamepad;
import flixel.input.gamepad.FlxGamepadInputID;
import flixel.input.gamepad.FlxGamepadManager;

using StringTools;

class ControlsSubState extends MusicBeatSubstate
{
	var curSelected:Int = 0;
	var curAlt:Bool = false;

	//Show on gamepad - Display name - Save file key - Rebind display name
	var options:Array<Dynamic> = [
		[true, 'NOTES'],
		[true, 'Left', 'note_left', 'Note Left'],
		[true, 'Down', 'note_down', 'Note Down'],
		[true, 'Up', 'note_up', 'Note Up'],
		[true, 'Right', 'note_right', 'Note Right'],
		[true],
		[true, 'UI'],
		[true, 'Left', 'ui_left', 'UI Left'],
		[true, 'Down', 'ui_down', 'UI Down'],
		[true, 'Up', 'ui_up', 'UI Up'],
		[true, 'Right', 'ui_right', 'UI Right'],
		[true],
		[true, 'Reset', 'reset', 'Reset'],
		[true, 'Accept', 'accept', 'Accept'],
		[true, 'Back', 'back', 'Back'],
		[true, 'Capture', 'screenshot', 'Capture'],
		[true, 'Pause', 'pause', 'Pause'],
		[false],
		[false, 'V-SLICE'],
		[true,"Chr menu","char_select","Character Menu"],
		[true,"FP left","bar_left","Freeplay left"],
		[true,"FP right","bar_right","Freeplay right"],
		[true,"Favorite","favorite","Freeplay favorite"],
		[false],
		[false, 'VOLUME'],
		[false, 'Mute', 'volume_mute', 'Volume Mute'],
		[false, 'Up', 'volume_up', 'Volume Up'],
		[false, 'Down', 'volume_down', 'Volume Down'],
		[false],
		[false, 'DEBUG'],
		[false, 'Key 1', 'debug_1', 'Debug Key #1'],
		[false, 'Key 2', 'debug_2', 'Debug Key #2']
	];
	var curOptions:Array<Int>;
	var curOptionsValid:Array<Int>;
	static var defaultKey:String = 'Reset to Default Keys';

	var bg:FlxSprite;
	var grpDisplay:FlxTypedGroup<FlxText>;
	var grpOptions:FlxTypedGroup<FlxText>;
	var grpBinds:FlxTypedGroup<FlxText>;
	
	var highlightBox:FlxSprite;
	var altBox:FlxSprite;
	var pageText:FlxText;

	var gamepadColor:FlxColor = 0xfffd7194;
	var keyboardColor:FlxColor = 0xff7192fd;
	var onKeyboardMode:Bool = true;
	
	var controllerTxt:FlxText;
	var lastID:Int = 0;
	var MAX_PER_PAGE:Int = 11;
	
	public function new()
	{
		controls.isInSubstate = true;
		super();

		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Controls Menu", null);
		#end

		options.push([true]);
		options.push([true]);
		options.push([true, defaultKey]);

		bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		add(bg);

		var header1 = new FlxText(20, 10, 0, "Controls Settings", 24);
		header1.setFormat(Paths.font("PressStart2P.ttf"), 20, 0xFFCCCCCC, LEFT); 
		add(header1);

		var header2 = new FlxText(20, 40, 0, "Up/Down=Select | Left/Right=Primary/Alt | Enter=Change", 24);
		header2.setFormat(Paths.font("PressStart2P.ttf"), 16, 0xFFCCCCCC, LEFT);
		add(header2);

		var header3 = new FlxText(20, 70, 0, "Press CTRL to swap Keyboard/Gamepad", 24);
		header3.setFormat(Paths.font("PressStart2P.ttf"), 16, FlxColor.YELLOW, LEFT);
		add(header3);

		highlightBox = new FlxSprite(20, 0).makeGraphic(FlxG.width - 40, 35, 0xFF888888);
		add(highlightBox);
		
		altBox = new FlxSprite(0, 0).makeGraphic(250, 35, FlxColor.WHITE);
		altBox.alpha = 0.3;
		add(altBox);

		grpDisplay = new FlxTypedGroup<FlxText>();
		add(grpDisplay);
		grpOptions = new FlxTypedGroup<FlxText>();
		add(grpOptions);
		grpBinds = new FlxTypedGroup<FlxText>();
		add(grpBinds);

		controllerTxt = new FlxText(FlxG.width - 300, 10, 280, "Mode: Keyboard", 24);
		controllerTxt.setFormat(Paths.font("PressStart2P.ttf"), 16, keyboardColor, RIGHT);
		add(controllerTxt);

		var bottomBg = new FlxSprite(20, FlxG.height - 40).makeGraphic(FlxG.width - 40, 30, 0xFF888888);
		add(bottomBg);

		var escTxt = new FlxText(FlxG.width - 200, FlxG.height - 38, 180, "ESC=Back", 24);
		escTxt.setFormat(Paths.font("PressStart2P.ttf"), 16, FlxColor.BLACK, RIGHT);
		add(escTxt);

		pageText = new FlxText(FlxG.width - 250, FlxG.height - 70, 230, "", 24);
		pageText.setFormat(Paths.font("PressStart2P.ttf"), 16, 0xFFCCCCCC, RIGHT);
		add(pageText);

		createTexts();
		#if TOUCH_CONTROLS_ALLOWED
		addTouchPad('NONE', 'B');
		#end
	}

	function createTexts()
	{
		curOptions = [];
		curOptionsValid = [];
		grpDisplay.forEachAlive(function(text:FlxText) text.destroy());
		grpOptions.forEachAlive(function(text:FlxText) text.destroy());
		grpBinds.forEachAlive(function(text:FlxText) text.destroy());
		grpDisplay.clear();
		grpOptions.clear();
		grpBinds.clear();

		var myID:Int = 0;
		for (i => option in options)
		{
			if(onKeyboardMode || option[0])
			{
				if(option.length > 1)
				{
					var isCentered:Bool = (option.length < 3);
					var isDefaultKey:Bool = (option[1] == defaultKey);
					var isDisplayKey:Bool = (isCentered && !isDefaultKey);

					var str:String = option[1];
					var keyStr:String = option[2];
					if(isDefaultKey) str = Language.getPhrase(str);

					var displayText = !isDisplayKey ? Language.getPhrase('key_$keyStr', str) : Language.getPhrase('keygroup_$str', str);
					
					var text:FlxText = new FlxText(60, 0, 0, displayText, 16);
					text.setFormat(Paths.font("PressStart2P.ttf"), 16, 0xFFCCCCCC, LEFT);
					text.ID = myID;
					lastID = myID;

					if(!isDisplayKey)
					{
						grpOptions.add(text);
						curOptions.push(i);
						curOptionsValid.push(myID);
					}
					else 
					{
						text.color = FlxColor.YELLOW;
						text.screenCenter(X);
						grpDisplay.add(text);
					}

					if(isDefaultKey)
					{
						text.screenCenter(X);
						text.color = 0xFFCCCCCC;
					}

					if(!isCentered && !isDefaultKey) 
					{
						addKeyText(text, option, myID);
					}
				}
				myID++;
			}
		}
		updateText();
	}

	function addKeyText(text:FlxText, option:Array<Dynamic>, id:Int)
	{
		var keys:Array<Null<FlxKey>> = ClientPrefs.keyBinds.get(option[2]);
		if(keys == null && onKeyboardMode)
			keys = ClientPrefs.defaultKeys.get(option[2]).copy();

		var gmpds:Array<Null<FlxGamepadInputID>> = ClientPrefs.gamepadBinds.get(option[2]);
		if(gmpds == null && !onKeyboardMode)
			gmpds = ClientPrefs.defaultButtons.get(option[2]).copy();

		for (n in 0...2)
		{
			var key:String = null;
			if(onKeyboardMode)
				key = InputFormatter.getKeyName((keys[n] != null) ? keys[n] : NONE);
			else
				key = InputFormatter.getGamepadName((gmpds[n] != null) ? gmpds[n] : NONE);

			var attach:FlxText = new FlxText(600 + (n * 300), 0, 0, key, 16);
			attach.setFormat(Paths.font("PressStart2P.ttf"), 16, 0xFFCCCCCC, LEFT);
			attach.ID = id; 
			
			grpBinds.add(attach);
			playstationCheck(attach);
		}
	}

	function playstationCheck(alpha:FlxText)
	{
		if(onKeyboardMode) return;

		var gamepad:FlxGamepad = FlxG.gamepads.firstActive;
		var model:FlxGamepadModel = gamepad != null ? gamepad.detectedModel : UNKNOWN;
		if(model == PS4)
		{
			switch(alpha.text)
			{
				case '[': alpha.text = 'Square';
				case ']': alpha.text = 'Triangle';
			}
		}
	}

	function updateBind(rowID:Int, altNum:Int, text:String)
	{
		var matchIndex = 0;
		for (bind in grpBinds.members)
		{
			if (bind.ID == rowID)
			{
				if (matchIndex == altNum)
				{
					bind.text = text;
					playstationCheck(bind);
					return;
				}
				matchIndex++;
			}
		}
	}

	var binding:Bool = false;
	var holdingEsc:Float = 0;
	var bindingBlack:FlxSprite;
	var bindingText:FlxText;
	var bindingText2:FlxText;

	var timeForMoving:Float = 0.1;
	override function update(elapsed:Float)
	{
		if(timeForMoving > 0)
		{
			timeForMoving = Math.max(0, timeForMoving - elapsed);
			super.update(elapsed);
			return;
		}

		if(!binding)
		{
			if(#if TOUCH_CONTROLS_ALLOWED touchPad.buttonB.justPressed || #end FlxG.keys.justPressed.ESCAPE || FlxG.gamepads.anyJustPressed(B))
			{
				controls.isInSubstate = false;
				close();
				return;
			}
			if(FlxG.keys.justPressed.CONTROL || FlxG.gamepads.anyJustPressed(LEFT_SHOULDER) || FlxG.gamepads.anyJustPressed(RIGHT_SHOULDER)) swapMode();

			if(FlxG.keys.justPressed.LEFT || FlxG.keys.justPressed.RIGHT || FlxG.gamepads.anyJustPressed(DPAD_LEFT) || FlxG.gamepads.anyJustPressed(DPAD_RIGHT) ||
				FlxG.gamepads.anyJustPressed(LEFT_STICK_DIGITAL_LEFT) || FlxG.gamepads.anyJustPressed(LEFT_STICK_DIGITAL_RIGHT)) updateAlt(true);

			if(FlxG.keys.justPressed.UP || FlxG.gamepads.anyJustPressed(DPAD_UP) || FlxG.gamepads.anyJustPressed(LEFT_STICK_DIGITAL_UP)) updateText(-1);
			else if(FlxG.keys.justPressed.DOWN || FlxG.gamepads.anyJustPressed(DPAD_DOWN) || FlxG.gamepads.anyJustPressed(LEFT_STICK_DIGITAL_DOWN)) updateText(1);

			if(FlxG.keys.justPressed.ENTER || FlxG.gamepads.anyJustPressed(START) || FlxG.gamepads.anyJustPressed(A))
			{
				if(options[curOptions[curSelected]][1] != defaultKey)
				{
					bindingBlack = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
					bindingBlack.alpha = 0;
					FlxTween.tween(bindingBlack, {alpha: 0.8}, 0.35, {ease: FlxEase.linear});
					add(bindingBlack);

					bindingText = new FlxText(0, 160, FlxG.width, Language.getPhrase('controls_rebinding', 'Rebinding {1}', [options[curOptions[curSelected]][3]]), 32);
					bindingText.setFormat(Paths.font("PressStart2P.ttf"), 20, FlxColor.WHITE, CENTER);
					add(bindingText);

					final escape:String = (controls.mobileC) ? "B" : "ESC";
					final backspace:String = (controls.mobileC) ? "C" : "Backspace";
					
					bindingText2 = new FlxText(0, 340, FlxG.width, Language.getPhrase('controls_rebinding2', 'Hold {1} to Cancel\nHold {2} to Delete', [escape, backspace]), 24);
					bindingText2.setFormat(Paths.font("PressStart2P.ttf"), 16, FlxColor.WHITE, CENTER);
					add(bindingText2);

					binding = true;
					holdingEsc = 0;
					ClientPrefs.toggleVolumeKeys(false);
					FlxG.sound.play(Paths.sound('scrollMenu'));
				}
				else
				{
					ClientPrefs.resetKeys(!onKeyboardMode);
					ClientPrefs.reloadVolumeKeys();
					var lastSel:Int = curSelected;
					createTexts();
					curSelected = lastSel;
					updateText();
					FlxG.sound.play(Paths.sound('cancelMenu'));
				}
			}
		}
		else
		{
			var altNum:Int = curAlt ? 1 : 0;
			var curOption:Array<Dynamic> = options[curOptions[curSelected]];
			if(FlxG.keys.pressed.ESCAPE || FlxG.gamepads.anyPressed(B))
			{
				holdingEsc += elapsed;
				if(holdingEsc > 0.5)
				{
					FlxG.sound.play(Paths.sound('cancelMenu'));
					closeBinding();
				}
			}
			else if (FlxG.keys.pressed.BACKSPACE || FlxG.gamepads.anyPressed(BACK))
			{
				holdingEsc += elapsed;
				if(holdingEsc > 0.5)
				{
					if (onKeyboardMode)
						ClientPrefs.keyBinds.get(curOption[2])[altNum] = NONE;
					else
						ClientPrefs.gamepadBinds.get(curOption[2])[altNum] = NONE;
					ClientPrefs.clearInvalidKeys(curOption[2]);
					updateBind(curOptionsValid[curSelected], altNum, onKeyboardMode ? InputFormatter.getKeyName(NONE) : InputFormatter.getGamepadName(NONE));
					FlxG.sound.play(Paths.sound('cancelMenu'));
					closeBinding();
				}
			}
			else
			{
				holdingEsc = 0;
				var changed:Bool = false;
				var curKeys:Array<FlxKey> = ClientPrefs.keyBinds.get(curOption[2]);
				var curButtons:Array<FlxGamepadInputID> = ClientPrefs.gamepadBinds.get(curOption[2]);

				if(onKeyboardMode)
				{
					if(FlxG.keys.justPressed.ANY || FlxG.keys.justReleased.ANY)
					{
						var keyPressed:Int = FlxG.keys.firstJustPressed();
						var keyReleased:Int = FlxG.keys.firstJustReleased();
						if (keyPressed > -1 && keyPressed != FlxKey.ESCAPE && keyPressed != FlxKey.BACKSPACE)
						{
							curKeys[altNum] = keyPressed;
							changed = true;
						}
						else if (keyReleased > -1 && (keyReleased == FlxKey.ESCAPE || keyReleased == FlxKey.BACKSPACE))
						{
							curKeys[altNum] = keyReleased;
							changed = true;
						}
					}
				}
				else if(FlxG.gamepads.anyJustPressed(ANY) || FlxG.gamepads.anyJustPressed(LEFT_TRIGGER) || FlxG.gamepads.anyJustPressed(RIGHT_TRIGGER) || FlxG.gamepads.anyJustReleased(ANY))
				{
					var keyPressed:Null<FlxGamepadInputID> = NONE;
					var keyReleased:Null<FlxGamepadInputID> = NONE;
					if(FlxG.gamepads.anyJustPressed(LEFT_TRIGGER)) keyPressed = LEFT_TRIGGER; 
					else if(FlxG.gamepads.anyJustPressed(RIGHT_TRIGGER)) keyPressed = RIGHT_TRIGGER; 
					else
					{
						for (i in 0...FlxG.gamepads.numActiveGamepads)
						{
							var gamepad:FlxGamepad = FlxG.gamepads.getByID(i);
							if(gamepad != null)
							{
								keyPressed = gamepad.firstJustPressedID();
								keyReleased = gamepad.firstJustReleasedID();

								if(keyPressed == null) keyPressed = NONE;
								if(keyReleased == null) keyReleased = NONE;
								if(keyPressed != NONE || keyReleased != NONE) break;
							}
						}
					}

					if (keyPressed != NONE && keyPressed != FlxGamepadInputID.BACK && keyPressed != FlxGamepadInputID.B)
					{
						curButtons[altNum] = keyPressed;
						changed = true;
					}
					else if (keyReleased != NONE && (keyReleased == FlxGamepadInputID.BACK || keyReleased == FlxGamepadInputID.B))
					{
						curButtons[altNum] = keyReleased;
						changed = true;
					}
				}

				if(changed)
				{
					if (onKeyboardMode)
					{
						if(curKeys[altNum] == curKeys[1 - altNum])
							curKeys[1 - altNum] = FlxKey.NONE;
					}
					else
					{
						if(curButtons[altNum] == curButtons[1 - altNum])
							curButtons[1 - altNum] = FlxGamepadInputID.NONE;
					}

					var option:String = options[curOptions[curSelected]][2];
					ClientPrefs.clearInvalidKeys(option);
					for (n in 0...2)
					{
						var key:String = null;
						if(onKeyboardMode)
						{
							var savKey:Array<Null<FlxKey>> = ClientPrefs.keyBinds.get(option);
							key = InputFormatter.getKeyName(savKey[n] != null ? savKey[n] : NONE);
						}
						else
						{
							var savKey:Array<Null<FlxGamepadInputID>> = ClientPrefs.gamepadBinds.get(option);
							key = InputFormatter.getGamepadName(savKey[n] != null ? savKey[n] : NONE);
						}
						updateBind(curOptionsValid[curSelected], n, key);
					}
					FlxG.sound.play(Paths.sound('confirmMenu'));
					closeBinding();
				}
			}
		}
		super.update(elapsed);
	}

	function closeBinding()
	{
		binding = false;
		bindingBlack.destroy();
		remove(bindingBlack);

		bindingText.destroy();
		remove(bindingText);

		bindingText2.destroy();
		remove(bindingText2);
		ClientPrefs.reloadVolumeKeys();
	}

	function updateText(?change:Int = 0)
	{
		curSelected = FlxMath.wrap(curSelected + change, 0, curOptions.length - 1);
		var rowID = curOptionsValid[curSelected];

		var totalPages = Math.ceil((lastID + 1) / MAX_PER_PAGE);
		var curPage = Math.floor(rowID / MAX_PER_PAGE);

		if (totalPages > 1)
			pageText.text = "Page " + (curPage + 1) + " / " + totalPages;
		else
			pageText.text = "";

		var startY = 100;

		grpOptions.forEachAlive(function(item:FlxText)
		{
			if (item.ID >= curPage * MAX_PER_PAGE && item.ID < (curPage + 1) * MAX_PER_PAGE)
			{
				item.visible = true;
				item.y = startY + ((item.ID % MAX_PER_PAGE) * 40);
				item.color = 0xFFCCCCCC; 
			}
			else
			{
				item.visible = false;
			}
		});

		grpBinds.forEachAlive(function(item:FlxText)
		{
			if (item.ID >= curPage * MAX_PER_PAGE && item.ID < (curPage + 1) * MAX_PER_PAGE)
			{
				item.visible = true;
				item.y = startY + ((item.ID % MAX_PER_PAGE) * 40);
				item.color = 0xFFCCCCCC;
			}
			else
			{
				item.visible = false;
			}
		});

		grpDisplay.forEachAlive(function(item:FlxText)
		{
			if (item.ID >= curPage * MAX_PER_PAGE && item.ID < (curPage + 1) * MAX_PER_PAGE)
			{
				item.visible = true;
				item.y = startY + ((item.ID % MAX_PER_PAGE) * 40);
				
				if (item.text == Language.getPhrase(defaultKey))
					item.color = 0xFFCCCCCC;
				else
					item.color = FlxColor.YELLOW;
			}
			else
			{
				item.visible = false;
			}
		});

		var activeY = startY + ((rowID % MAX_PER_PAGE) * 40);
		highlightBox.y = activeY - 9;

		updateAlt();
		FlxG.sound.play(Paths.sound('scrollMenu'));
	}

	function swapMode()
	{
		onKeyboardMode = !onKeyboardMode;
		controllerTxt.text = "Mode: " + (onKeyboardMode ? "Keyboard" : "Gamepad");
		controllerTxt.color = onKeyboardMode ? keyboardColor : gamepadColor;

		curSelected = 0;
		curAlt = false;
		createTexts();
	}

	function updateAlt(?doSwap:Bool = false)
	{
		if(doSwap)
		{
			curAlt = !curAlt;
			FlxG.sound.play(Paths.sound('scrollMenu'));
		}
		
		if (options[curOptions[curSelected]][1] != defaultKey) {
			altBox.y = highlightBox.y;
			altBox.x = 590 + (curAlt ? 300 : 0);
			altBox.visible = true;
		} else {
			altBox.visible = false;
		}
	}
}