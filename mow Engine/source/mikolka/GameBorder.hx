package mikolka;

import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.events.MouseEvent;
import openfl.events.Event;
import openfl.Lib;
import openfl.Assets;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.system.System;
#if sys
import sys.FileSystem;
#end

class GameBorder extends Sprite
{
	var bg:Sprite;
	var titleText:TextField;
	var closeButton:Sprite;
	var maximizeButton:Sprite;
	var minimizeButton:Sprite;
	var iconBitmap:Bitmap;
	var maxIconSprite:Sprite;


	public static final BORDER_HEIGHT:Int = 40;
	public static final BTN_WIDTH:Int = 48;

	public function new()
	{
		super();

		// Background setup
		bg = new Sprite();
		drawBackground(Lib.current.stage.stageWidth);
		addChild(bg);

		// Window dragging is handled by native Win32 WM_NCHITTEST in Main.hx.

		// Load Icon
		loadGameLogo();

		// Game Title
		titleText = new TextField();
		titleText.text = "Lost Bloom Rewire"; 

		var fontPath = "assets/fonts/Bro.ttf";
		if (!Assets.exists(fontPath)) fontPath = "assets/fonts/Bro.TTF";

		var fontName = "_sans";
		if (Assets.exists(fontPath)) {
			var loadedFont = Assets.getFont(fontPath);
			if (loadedFont != null) {
				fontName = loadedFont.fontName;
				titleText.embedFonts = true;
			}
		}

		var format = new TextFormat(fontName, 16, 0xFFFFFF, false); 
		titleText.defaultTextFormat = format;
		titleText.selectable = false;
		titleText.mouseEnabled = false;
		titleText.x = 42; 
		titleText.y = 8;
		titleText.width = 500;
		addChild(titleText);

		// Minimize Button
		minimizeButton = createButton("min", 0x444444);
		minimizeButton.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) {
			e.stopPropagation();
			if (Lib.current.stage.window != null)
				Lib.current.stage.window.minimized = true;
		});
		addChild(minimizeButton);

		// Maximize Button
		maximizeButton = createButton("max", 0x444444);
		maximizeButton.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) {
			e.stopPropagation();
			if (Lib.current.stage.window != null) {
				if (Lib.current.stage.window.fullscreen) {
					Lib.current.stage.window.fullscreen = false;
				} else {
					Lib.current.stage.window.maximized = !Lib.current.stage.window.maximized;
				}
				drawMaximizeIcon();
			}
		});
		addChild(maximizeButton);

		// Close Button
		closeButton = createButton("close", 0xE81123);
		closeButton.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) {
			e.stopPropagation();
			if (Lib.current.stage.window != null)
				Lib.current.stage.window.close();
			else
				System.exit(0);
		});
		addChild(closeButton);

		updateGameSize(Lib.current.stage.stageWidth, Lib.current.stage.stageHeight);
	}

	function drawBackground(width:Int)
	{
		bg.graphics.clear();
		bg.graphics.beginFill(0x202020, 0.95); 
		bg.graphics.drawRect(0, 0, width, BORDER_HEIGHT);
		bg.graphics.endFill();

		bg.graphics.beginFill(0x333333, 1.0);
		bg.graphics.drawRect(0, BORDER_HEIGHT - 1, width, 1);
		bg.graphics.endFill();
	}

	function loadGameLogo()
	{
		var possiblePaths = [
			"art/desktop/icon.png", 
			"icon.png", 
			"assets/shared/images/icon.png"
		];
		var loaded = false;

		for (path in possiblePaths) {
			try {
				var bData:BitmapData = null;
				if (Assets.exists(path)) {
					bData = Assets.getBitmapData(path);
				} 
				#if sys
				else if (FileSystem.exists(path)) {
					bData = BitmapData.fromFile(path);
				}
				#end

				if (bData != null) {
					iconBitmap = new Bitmap(bData);

					// เก็บสัดส่วนจริงของรูปไอคอน ไม่บีบเป็น 22x22 ตรงๆ (จะทำให้รูปเบี้ยว)
					var targetSize:Float = 24;
					var scale:Float = targetSize / Math.max(bData.width, bData.height);
					iconBitmap.width = bData.width * scale;
					iconBitmap.height = bData.height * scale;
					iconBitmap.x = 12;
					iconBitmap.y = (BORDER_HEIGHT - iconBitmap.height) / 2;
					iconBitmap.smoothing = true;
					addChild(iconBitmap);
					loaded = true;
					break;
				}
			} catch(e:Dynamic) {}
		}

		if (!loaded) {
			var fallbackIcon = new Sprite();
			fallbackIcon.graphics.beginFill(0x00E5FF);
			fallbackIcon.graphics.drawCircle(23, 20, 10);
			fallbackIcon.graphics.endFill();
			fallbackIcon.graphics.beginFill(0xFFFFFF);
			fallbackIcon.graphics.drawCircle(23, 20, 4);
			fallbackIcon.graphics.endFill();
			addChild(fallbackIcon);
		}
	}

	function createButton(type:String, hoverColor:Int):Sprite
	{
		var btn = new Sprite();
		btn.buttonMode = true;       
		btn.mouseChildren = false;   

		var drawNormal = function() {
			btn.graphics.clear();
			btn.graphics.beginFill(0xFFFFFF, 0.001); 
			btn.graphics.drawRect(0, 0, BTN_WIDTH, BORDER_HEIGHT);
			btn.graphics.endFill();
		};

		var drawHover = function() {
			btn.graphics.clear();
			btn.graphics.beginFill(hoverColor, 1.0); 
			btn.graphics.drawRect(0, 0, BTN_WIDTH, BORDER_HEIGHT);
			btn.graphics.endFill();
		};

		drawNormal();

		var icon = new Sprite();
		icon.graphics.lineStyle(1.5, 0xFFFFFF, 1.0);

		if (type == "min") {
			icon.graphics.moveTo(18, 20);
			icon.graphics.lineTo(30, 20);
		} else if (type == "max") {
			maxIconSprite = icon;
			drawMaximizeIcon();
		} else if (type == "close") {
			icon.graphics.moveTo(19, 14);
			icon.graphics.lineTo(29, 24);
			icon.graphics.moveTo(29, 14);
			icon.graphics.lineTo(19, 24);
		}

		btn.addChild(icon);

		btn.addEventListener(MouseEvent.MOUSE_OVER, function(e:MouseEvent) drawHover());
		btn.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent) drawNormal());

		return btn;
	}

	function drawMaximizeIcon()
	{
		if (maxIconSprite == null) return;
		maxIconSprite.graphics.clear();
		maxIconSprite.graphics.lineStyle(1.5, 0xFFFFFF, 1.0);

		var isMax = (Lib.current.stage.window != null && (Lib.current.stage.window.maximized || Lib.current.stage.window.fullscreen));

		if (isMax) {
			maxIconSprite.graphics.drawRect(21, 13, 8, 8);
			maxIconSprite.graphics.drawRect(18, 16, 8, 8);
		} else {
			maxIconSprite.graphics.drawRect(18, 14, 11, 11);
		}
	}

	public function updateGameSize(width:Int, height:Int):Void
	{
		drawBackground(width);

		if (closeButton != null) closeButton.x = width - BTN_WIDTH;
		if (maximizeButton != null) maximizeButton.x = width - (BTN_WIDTH * 2);
		if (minimizeButton != null) minimizeButton.x = width - (BTN_WIDTH * 3);

		drawMaximizeIcon();
	}
}