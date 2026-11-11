package mikolka.vslice.ui.title;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxTimer; // เพิ่มการเรียกใช้ FlxTimer
import states.InitState;
import lime.app.Application;

class WarningState extends flixel.FlxState 
{
    var titleText:FlxText;
    var bodyText:FlxText;
    var hintText:FlxText;
    
    var canContinue:Bool = false;
    var isTransitioning:Bool = false;

    // ขนาดพื้นฐาน
    var baseWidth:Int = 1280;
    var baseHeight:Int = 720;

    override public function create():Void
    {
        super.create();

        // ตรวจสอบว่าหน้าต่างอยู่ขนาดปกติและกลางจอ
        var window = Application.current.window;
        if (window != null) {
            var dpiScale = window.scale;
            var w = Std.int(baseWidth * dpiScale);
            var h = Std.int(baseHeight * dpiScale);
            
            FlxG.resizeWindow(w, h);
            window.x = Std.int((window.display.currentMode.width - w) / 2);
            window.y = Std.int((window.display.currentMode.height - h) / 2);
        }

        var bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
        add(bg);

        titleText = new FlxText(0, 100, FlxG.width, "WARNING", 72);
        titleText.setFormat(Paths.font("vcr.ttf"), 84, FlxColor.RED, CENTER, OUTLINE, FlxColor.BLACK);
        titleText.screenCenter(X);
        add(titleText);

        var warnMsg:String = "This mod contains flashing lights and disturbing content.\nProceed with caution.";
        bodyText = new FlxText(0, 0, FlxG.width * 0.9, warnMsg, 32);
        bodyText.setFormat(Paths.font("vcr.ttf"), 36, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
        bodyText.screenCenter(XY);
        bodyText.alpha = 0;
        add(bodyText);

        hintText = new FlxText(0, FlxG.height - 80, FlxG.width, "Press ENTER to Continue", 24);
        hintText.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.GRAY, CENTER);
        hintText.screenCenter(X);
        add(hintText);

        FlxTween.tween(bodyText, {alpha: 1}, 1.0, {
            ease: FlxEase.quadInOut, 
            onComplete: function(twn:FlxTween) {
                canContinue = true;
            }
        });
    }

    override function update(elapsed:Float)
    {
        super.update(elapsed);

        if (canContinue && !isTransitioning && (FlxG.keys.justPressed.ENTER || FlxG.keys.justPressed.SPACE))
        {
            isTransitioning = true;

            var window = Application.current.window;
            var dpiScale = (window != null) ? window.scale : 1.0;
            var displayW = window.display.currentMode.width;
            var displayH = window.display.currentMode.height;

            // --- เอฟเฟกต์ Zoom Out (ขยายหน้าต่างช้าลง ปรับเวลาเป็น 1.5 วินาที) ---
            FlxTween.num(1.0, 1.2, 1.5, {ease: FlxEase.expoIn}, function(v:Float) {
                var targetW:Int = Std.int(baseWidth * v * dpiScale);
                var targetH:Int = Std.int(baseHeight * v * dpiScale);
                
                FlxG.resizeWindow(targetW, targetH);
                
                // คอยจัดให้หน้าต่างอยู่กลางจอตลอดการขยาย
                window.x = Std.int((displayW - targetW) / 2);
                window.y = Std.int((displayH - targetH) / 2);
            });

            var transitionOverlay = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
            transitionOverlay.alpha = 0;
            add(transitionOverlay);

            // ทำให้หน้าจอเฟดดำช้าลงตามเวลาซูม (1.5 วินาที)
            FlxTween.tween(transitionOverlay, {alpha: 1}, 1.5, {
                onComplete: function(twn:FlxTween) {
                    
                    // --- รอ 2 วินาทีก่อนค่อยเปลี่ยนหน้า ---
                    new FlxTimer().start(2.0, function(tmr:FlxTimer) {
                        // รีเซ็ตขนาดหน้าต่างกลับมาเป็น 1280x720 ก่อนเข้าหน้า InitState
                        FlxG.resizeWindow(baseWidth, baseHeight);
                        window.x = Std.int((displayW - (baseWidth * dpiScale)) / 2);
                        window.y = Std.int((displayH - (baseHeight * dpiScale)) / 2);
                        
                        FlxG.switchState(new InitState()); 
                    });
                    
                }
            });
        }
    }
}