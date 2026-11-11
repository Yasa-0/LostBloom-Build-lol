package options;

import mikolka.funkin.custom.mobile.MobileScaleMode;
import mobile.objects.TouchZone;
import flixel.input.keyboard.FlxKey;
import flixel.input.gamepad.FlxGamepad;
import flixel.input.gamepad.FlxGamepadInputID;
import flixel.input.gamepad.FlxGamepadManager;
import options.Option;
import backend.InputFormatter;
import mobile.options.MobileOptionsSubState;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.math.FlxMath;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;

using StringTools;

class BaseOptionsMenu extends MusicBeatSubstate
{
	private var curOption:Option = null;
	private var curSelected:Int = 0;
	private var optionsArray:Array<Option>;

	private var grpOptions:FlxTypedGroup<FlxText>;
	private var grpTexts:FlxTypedGroup<FlxText>;

	private var descText:FlxText;
	private var highlightBox:FlxSprite;
	private var pageText:FlxText;

	public var title:String;
	public var rpcTitle:String;

	public var bg:FlxSprite;
	private var oldMusicVolume:Float = -1;
	var MAX_PER_PAGE:Int = 11;

	public function new()
	{
		controls.isInSubstate = true;
		super();

		if (FlxG.sound.music != null)
		{
			oldMusicVolume = FlxG.sound.music.volume;
			FlxG.sound.music.volume = 0; 
		}

		// เช็คให้มั่นใจว่า inRoomMusic มีอยู่จริงถึงจะเปิดเสียง ถ้าเป็น null จะเงียบไปเลย
		if (OptionsState.inRoomMusic != null && OptionsState.inRoomMusic.active)
		{
			OptionsState.inRoomMusic.time = FlxG.sound.music.time;
			OptionsState.inRoomMusic.volume = 0.7;
		}

		FlxG.mouse.visible = true;

		if (title == null)
			title = 'Options';
		if (rpcTitle == null)
			rpcTitle = 'Options Menu';

		#if DISCORD_ALLOWED
		DiscordClient.changePresence(rpcTitle, null);
		#end

		bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		add(bg);

		var header1 = new FlxText(20, 10, 0, "Choose Advanced Options for: " + title, 24);
		header1.setFormat(Paths.font("PressStart2P.ttf"), 20, 0xFFCCCCCC, LEFT); 
		add(header1);

		var header2 = new FlxText(20, 40, 0, "Use the up and down arrow keys to move the highlight to your choice.", 24);
		header2.setFormat(Paths.font("PressStart2P.ttf"), 16, 0xFFCCCCCC, LEFT);
		add(header2);

		highlightBox = new FlxSprite(20, 0).makeGraphic(FlxG.width - 40, 35, 0xFF888888);
		add(highlightBox);

		grpOptions = new FlxTypedGroup<FlxText>();
		add(grpOptions);

		grpTexts = new FlxTypedGroup<FlxText>();
		add(grpTexts);

		descText = new FlxText(20, FlxG.height - 120, FlxG.width - 40, "Description: ", 24);
		descText.setFormat(Paths.font("PressStart2P.ttf"), 16, 0xFFCCCCCC, LEFT);
		add(descText);

		var bottomBg = new FlxSprite(20, FlxG.height - 40).makeGraphic(FlxG.width - 40, 30, 0xFF888888);
		add(bottomBg);

		var enterTxt = new FlxText(20, FlxG.height - 38, 0, "ENTER=Choose", 24);
		enterTxt.setFormat(Paths.font("PressStart2P.ttf"), 16, FlxColor.BLACK, LEFT);
		add(enterTxt);

		var escTxt = new FlxText(FlxG.width - 200, FlxG.height - 38, 180, "ESC=Cancel", 24);
		escTxt.setFormat(Paths.font("PressStart2P.ttf"), 16, FlxColor.BLACK, RIGHT);
		add(escTxt);

		pageText = new FlxText(FlxG.width - 250, FlxG.height - 70, 230, "", 24);
		pageText.setFormat(Paths.font("PressStart2P.ttf"), 16, 0xFFCCCCCC, RIGHT);
		add(pageText);

		for (i in 0...optionsArray.length)
		{
			var optionText:FlxText = new FlxText(60, 0, 0, optionsArray[i].name, 16);
			optionText.setFormat(Paths.font("PressStart2P.ttf"), 16, 0xFFCCCCCC, LEFT);
			optionText.ID = i;
			grpOptions.add(optionText);

			var rightSideX:Float = 750;

			if (optionsArray[i].type == BOOL)
			{
				var isTrue = Std.string(optionsArray[i].getValue()) == 'true';
				var boolText:FlxText = new FlxText(rightSideX, optionText.y, 0, isTrue ? "ON" : "OFF", 16);
				boolText.setFormat(Paths.font("PressStart2P.ttf"), 16, isTrue ? FlxColor.GREEN : FlxColor.RED, LEFT);
				boolText.ID = i;
				grpTexts.add(boolText);
				optionsArray[i].child = boolText;
			}
			else
			{
				var valueText:FlxText = new FlxText(rightSideX, optionText.y, 0, '' + optionsArray[i].getValue(), 16);
				valueText.setFormat(Paths.font("PressStart2P.ttf"), 16, 0xFFCCCCCC, LEFT);
				valueText.ID = i;
				grpTexts.add(valueText);
				optionsArray[i].child = valueText;
			}
			updateTextFrom(optionsArray[i]);
		}

		changeSelection(0, true);
		reloadCheckboxes();

		#if TOUCH_CONTROLS_ALLOWED
		addTouchPad('LEFT_FULL', 'A_B_C');
		var button = new TouchZone(20, 100, FlxG.width - 40, FlxG.height - 250, FlxColor.PURPLE);
		var scroll = new ScrollableObject(-0.008, 100, 0, FlxG.width, FlxG.height, button);
		scroll.onPartialScroll.add(delta -> changeSelection(delta, false));
		scroll.onFullScrollSnap.add(() -> changeSelection(0, true));
		scroll.onTap.add(() -> { onAcceptPress(); });
		add(scroll);
		add(button);
		#end
	}

	override function close()
	{
		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.volume = (oldMusicVolume != -1) ? oldMusicVolume : 0;
		}
		super.close();
	}

	public function addOption(option:Option)
	{
		if (optionsArray == null || optionsArray.length < 1)
			optionsArray = [];
		optionsArray.push(option);
		return option;
	}

	var nextAccept:Int = 5;
	var holdTime:Float = 0;
	var holdValue:Float = 0;
	var bindingKey:Bool = false;
	var holdingEsc:Float = 0;
	var bindingBlack:FlxSprite;
	var bindingText:FlxText;
	var bindingText2:FlxText;

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (FlxG.sound.music != null && OptionsState.inRoomMusic != null && OptionsState.inRoomMusic.active)
		{
			if (Math.abs(OptionsState.inRoomMusic.time - FlxG.sound.music.time) > 20)
				OptionsState.inRoomMusic.time = FlxG.sound.music.time;
		}

		if (bindingKey)
		{
			bindingKeyUpdate(elapsed);
			return;
		}

		if (FlxG.mouse.wheel != 0)
		{
			FlxG.sound.play(Paths.sound('lick'));
			changeSelection(-FlxG.mouse.wheel, true);
		}

		if (FlxG.mouse.justMoved)
		{
			for (i in 0...grpOptions.members.length)
			{
				var item = grpOptions.members[i];
				if (item.visible && FlxG.mouse.y >= item.y && FlxG.mouse.y <= item.y + item.height && FlxG.mouse.x >= 20 && FlxG.mouse.x <= FlxG.width - 20)
				{
					if (curSelected != i)
					{
						curSelected = i;
						FlxG.sound.play(Paths.sound('lick'));
						changeSelection(0, true);
					}
					break;
				}
			}
		}

		if (controls.UI_UP_P)
		{
			FlxG.sound.play(Paths.sound('lick'));
			changeSelection(-1, true);
		}
		if (controls.UI_DOWN_P)
		{
			FlxG.sound.play(Paths.sound('lick'));
			changeSelection(1, true);
		}

		if (controls.BACK || (FlxG.mouse.justPressedRight)) 
		{
			close();
			FlxG.sound.play(Paths.sound('back'));
		}

		if (nextAccept <= 0)
		{
			var isMouseClicked = FlxG.mouse.justPressed;

			switch (curOption.type)
			{
				case BOOL | KEYBIND:
					if (controls.ACCEPT || isMouseClicked)
						onAcceptPress();
				default:
					if (controls.UI_LEFT || controls.UI_RIGHT || isMouseClicked)
					{
						var pressed = (controls.UI_LEFT_P || controls.UI_RIGHT_P || isMouseClicked);
						if (holdTime > 0.5 || pressed)
						{
							if (pressed)
							{
								var add:Dynamic = null;
								if (curOption.type != STRING)
								{
									if (isMouseClicked)
										add = (FlxG.mouse.x > FlxG.width / 2) ? curOption.changeValue : -curOption.changeValue;
									else
										add = controls.UI_LEFT ? -curOption.changeValue : curOption.changeValue;
								}

								switch (curOption.type)
								{
									case INT, FLOAT, PERCENT:
										holdValue = curOption.getValue() + add;
										if (holdValue < curOption.minValue)
											holdValue = curOption.minValue;
										else if (holdValue > curOption.maxValue)
											holdValue = curOption.maxValue;

										if (curOption.type == INT)
										{
											holdValue = Math.round(holdValue);
											curOption.setValue(holdValue);
										}
										else
										{
											holdValue = FlxMath.roundDecimal(holdValue, curOption.decimals);
											curOption.setValue(holdValue);
										}

									case STRING:
										var num:Int = curOption.curOption; 
										var isRight = isMouseClicked ? (FlxG.mouse.x > FlxG.width / 2) : controls.UI_RIGHT_P;

										if (!isRight)
											--num;
										else
											num++;

										if (num < 0)
											num = curOption.options.length - 1;
										else if (num >= curOption.options.length)
											num = 0;

										curOption.curOption = num;
										curOption.setValue(curOption.options[num]);

									default:
								}
								updateTextFrom(curOption);
								curOption.change();
								FlxG.sound.play(Paths.sound('lick'));
							}
							else if (curOption.type != STRING)
							{
								holdValue += curOption.scrollSpeed * elapsed * (controls.UI_LEFT ? -1 : 1);
								if (holdValue < curOption.minValue)
									holdValue = curOption.minValue;
								else if (holdValue > curOption.maxValue)
									holdValue = curOption.maxValue;

								switch (curOption.type)
								{
									case INT:
										curOption.setValue(Math.round(holdValue));

									case PERCENT:
										curOption.setValue(FlxMath.roundDecimal(holdValue, curOption.decimals));

									default:
								}
								updateTextFrom(curOption);
								curOption.change();
							}
						}

						if (curOption.type != STRING)
							holdTime += elapsed;
					}
					else if (controls.UI_LEFT_R || controls.UI_RIGHT_R)
					{
						if (holdTime > 0.5)
							FlxG.sound.play(Paths.sound('lick'));
						holdTime = 0;
					}
			}

			if (controls.RESET #if TOUCH_CONTROLS_ALLOWED || touchPad.buttonC.justPressed #end || FlxG.mouse.justPressedMiddle)
			{
				var leOption:Option = optionsArray[curSelected];
				if (leOption.type != KEYBIND)
				{
					leOption.setValue(leOption.defaultValue);
					if (leOption.type != BOOL)
					{
						if (leOption.type == STRING)
							leOption.curOption = leOption.options.indexOf(leOption.getValue());
						updateTextFrom(leOption);
					}
				}
				else
				{
					leOption.setValue(!Controls.instance.controllerMode ? leOption.defaultKeys.keyboard : leOption.defaultKeys.gamepad);
					updateBind(leOption);
				}
				leOption.change();
				FlxG.sound.play(Paths.sound('back'));
				reloadCheckboxes();
			}
		}

		if (nextAccept > 0)
		{
			nextAccept -= 1;
		}
	}

	function onAcceptPress()
	{
		switch (curOption.type)
		{
			case BOOL:
				FlxG.sound.play(Paths.sound('next'));
				curOption.setValue((curOption.getValue() == true) ? false : true);
				curOption.change();
				reloadCheckboxes();

			case KEYBIND:
				bindingBlack = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
				bindingBlack.alpha = 0;
				FlxTween.tween(bindingBlack, {alpha: 0.8}, 0.35, {ease: FlxEase.linear});
				add(bindingBlack);

				bindingText = new FlxText(0, 160, FlxG.width, Language.getPhrase('controls_rebinding', 'Rebinding {1}', [curOption.name]), 32);
				bindingText.setFormat(Paths.font("PressStart2P.ttf"), 20, FlxColor.WHITE, CENTER);
				add(bindingText);

				final escape:String = (controls.mobileC) ? "B" : "ESC";
				final backspace:String = (controls.mobileC) ? "C" : "Backspace";

				bindingText2 = new FlxText(0, 340, FlxG.width, Language.getPhrase('controls_rebinding2', 'Hold {1} to Cancel\nHold {2} to Delete', [escape, backspace]), 24);
				bindingText2.setFormat(Paths.font("PressStart2P.ttf"), 16, FlxColor.WHITE, CENTER);
				add(bindingText2);

				bindingKey = true;
				holdingEsc = 0;
				ClientPrefs.toggleVolumeKeys(false);
				FlxG.sound.play(Paths.sound('next'));
			default:
				return;
		}
	}

	function bindingKeyUpdate(elapsed:Float)
	{
		if (#if TOUCH_CONTROLS_ALLOWED touchPad.buttonB.pressed || #end FlxG.keys.pressed.ESCAPE || FlxG.gamepads.anyPressed(B))
		{
			holdingEsc += elapsed;
			if (holdingEsc > 0.5)
			{
				FlxG.sound.play(Paths.sound('back'));
				closeBinding();
			}
		}
		else if (#if TOUCH_CONTROLS_ALLOWED touchPad.buttonC.pressed || #end FlxG.keys.pressed.BACKSPACE || FlxG.gamepads.anyPressed(BACK))
		{
			holdingEsc += elapsed;
			if (holdingEsc > 0.5)
			{
				if (!controls.controllerMode)
					curOption.keys.keyboard = 'NONE';
				else
					curOption.keys.gamepad = 'NONE';
				updateBind(!controls.controllerMode ? InputFormatter.getKeyName(FlxKey.NONE) : InputFormatter.getGamepadName(FlxGamepadInputID.NONE));
				FlxG.sound.play(Paths.sound('back'));
				closeBinding();
			}
		}
		else
		{
			holdingEsc = 0;
			var changed:Bool = false;
			if (!controls.controllerMode)
			{
				if (FlxG.keys.justPressed.ANY || FlxG.keys.justReleased.ANY)
				{
					var keyPressed:FlxKey = cast(FlxG.keys.firstJustPressed(), FlxKey);
					var keyReleased:FlxKey = cast(FlxG.keys.firstJustReleased(), FlxKey);

					if (keyPressed != NONE && keyPressed != ESCAPE && keyPressed != BACKSPACE)
					{
						changed = true;
						curOption.keys.keyboard = keyPressed;
					}
					else if (keyReleased != NONE && (keyReleased == ESCAPE || keyReleased == BACKSPACE))
					{
						changed = true;
						curOption.keys.keyboard = keyReleased;
					}
				}
			}
			else if (FlxG.gamepads.anyJustPressed(ANY)
				|| FlxG.gamepads.anyJustPressed(LEFT_TRIGGER)
				|| FlxG.gamepads.anyJustPressed(RIGHT_TRIGGER)
				|| FlxG.gamepads.anyJustReleased(ANY))
			{
				var keyPressed:FlxGamepadInputID = NONE;
				var keyReleased:FlxGamepadInputID = NONE;
				if (FlxG.gamepads.anyJustPressed(LEFT_TRIGGER))
					keyPressed = LEFT_TRIGGER; 
				else if (FlxG.gamepads.anyJustPressed(RIGHT_TRIGGER))
					keyPressed = RIGHT_TRIGGER; 
				else
				{
					for (i in 0...FlxG.gamepads.numActiveGamepads)
					{
						var gamepad:FlxGamepad = FlxG.gamepads.getByID(i);
						if (gamepad != null)
						{
							keyPressed = gamepad.firstJustPressedID();
							keyReleased = gamepad.firstJustReleasedID();
							if (keyPressed != NONE || keyReleased != NONE)
								break;
						}
					}
				}

				if (keyPressed != NONE && keyPressed != FlxGamepadInputID.BACK && keyPressed != FlxGamepadInputID.B)
				{
					changed = true;
					curOption.keys.gamepad = keyPressed;
				}
				else if (keyReleased != NONE && (keyReleased == FlxGamepadInputID.BACK || keyReleased == FlxGamepadInputID.B))
				{
					changed = true;
					curOption.keys.gamepad = keyReleased;
				}
			}

			if (changed)
			{
				var key:String = null;
				if (!controls.controllerMode)
				{
					if (curOption.keys.keyboard == null)
						curOption.keys.keyboard = 'NONE';
					curOption.setValue(curOption.keys.keyboard);
					key = InputFormatter.getKeyName(FlxKey.fromString(curOption.keys.keyboard));
				}
				else
				{
					if (curOption.keys.gamepad == null)
						curOption.keys.gamepad = 'NONE';
					curOption.setValue(curOption.keys.gamepad);
					key = InputFormatter.getGamepadName(FlxGamepadInputID.fromString(curOption.keys.gamepad));
				}
				updateBind(key);
				FlxG.sound.play(Paths.sound('next'));
				closeBinding();
			}
		}
	}

	function updateBind(?text:String = null, ?option:Option = null)
	{
		if (option == null)
			option = curOption;
		if (text == null)
		{
			text = option.getValue();
			if (text == null)
				text = 'NONE';

			if (!controls.controllerMode)
				text = InputFormatter.getKeyName(FlxKey.fromString(text));
			else
				text = InputFormatter.getGamepadName(FlxGamepadInputID.fromString(text));
		}

		if (option.child != null)
		{
			var bind:FlxText = cast option.child;
			bind.text = text;
		}
	}

	function playstationCheck(text:FlxText)
	{
		return;
	}

	function closeBinding()
	{
		bindingKey = false;
		bindingBlack.destroy();
		remove(bindingBlack);

		bindingText.destroy();
		remove(bindingText);

		bindingText2.destroy();
		remove(bindingText2);
		ClientPrefs.toggleVolumeKeys(true);
	}

	function updateTextFrom(option:Option)
	{
		if (option.type == KEYBIND)
		{
			updateBind(option);
			return;
		}

		var text:String = option.displayFormat;
		var val:Dynamic = option.getValue();
		if (option.type == PERCENT)
			val *= 100;
		var def:Dynamic = option.defaultValue;
		option.text = text.replace('%v', val).replace('%d', def);

		if (option.type != BOOL && option.child != null)
		{
			var valText:FlxText = cast option.child;
			valText.text = "< " + option.text + " >"; 
		}
	}

	function changeSelection(change:Float = 0, usePrecision:Bool = false)
	{
		if (usePrecision)
		{
			curSelected = FlxMath.wrap(curSelected + Std.int(change), 0, optionsArray.length - 1);
		}
		else
		{
			var oldSelected = curSelected;
			curSelected = FlxMath.wrap(curSelected + Math.round(change), 0, optionsArray.length - 1);
			if (curSelected != oldSelected) FlxG.sound.play(Paths.sound('lick'));
		}
		
		descText.text = "Description: " + optionsArray[curSelected].description;

		var totalPages = Math.ceil(optionsArray.length / MAX_PER_PAGE);
		var curPage = Math.floor(curSelected / MAX_PER_PAGE);

		if (totalPages > 1)
			pageText.text = "Page " + (curPage + 1) + " / " + totalPages;
		else
			pageText.text = "";

		var startY = 100;
		for (num => item in grpOptions.members)
		{
			if (num >= curPage * MAX_PER_PAGE && num < (curPage + 1) * MAX_PER_PAGE)
			{
				item.visible = true;
				item.y = startY + ((num % MAX_PER_PAGE) * 35); 
				
				if (num == curSelected)
				{
					item.color = FlxColor.WHITE;
					highlightBox.y = item.y - 4;
				}
				else
				{
					item.color = 0xFFCCCCCC;
				}

				if (optionsArray[num].child != null)
				{
					var valText:FlxText = cast optionsArray[num].child;
					valText.y = item.y;
					
					if (optionsArray[num].type != BOOL)
					{
						valText.color = item.color;
					}
					
					valText.visible = true;
				}
			}
			else
			{
				item.visible = false;
				if (optionsArray[num].child != null)
				{
					var valText:FlxText = cast optionsArray[num].child;
					valText.visible = false;
				}
			}
		}

		curOption = optionsArray[curSelected]; 
	}

	function reloadCheckboxes()
	{
		for (option in optionsArray)
		{
			if (option.type == BOOL && option.child != null)
			{
				var isTrue = Std.string(option.getValue()) == 'true';
				var valText:FlxText = cast option.child;
				valText.text = isTrue ? "ON" : "OFF";
				valText.color = isTrue ? FlxColor.GREEN : FlxColor.RED;
			}
		}
	}
}