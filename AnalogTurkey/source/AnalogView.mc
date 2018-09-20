//
// Copyright 2016-2017 by Garmin Ltd. or its subsidiaries.
// Subject to Garmin SDK License Agreement and Wearables
// Application Developer Agreement.
//

using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.System;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.WatchUi;
using Toybox.Application;

var partialUpdatesAllowed = false;

// This implements an analog watch face
// Original design by Austen Harbour
class AnalogView extends WatchUi.WatchFace
{
    var font;
    var isAwake = false;
    var screenShape;
    var dndIcon;
    var offscreenBuffer;
    var dateBuffer;
    var turkeyBuffer;
    var curClip;
    var screenCenterPoint;
    var fullScreenRefresh;
    var backgroundTurkey;
    var turkeyIcon;
    var disableSeconds = false;

    // Initialize variables for this view
    function initialize() {
        WatchFace.initialize();
        screenShape = System.getDeviceSettings().screenShape;
        fullScreenRefresh = true;
        partialUpdatesAllowed = ( Toybox.WatchUi.WatchFace has :onPartialUpdate );
        disableSeconds = Application.getApp().getProperty("disableSeconds");
    }

    // Configure the layout of the watchface for this device
    function onLayout(dc) {

        //turkey dimentions: 150 x 150
        var xPos = dc.getWidth() / 2 - 75;
        var yPos = dc.getHeight() / 2 - 75 - 20;
        backgroundTurkey =
	        new WatchUi.Bitmap({
	        	:rezId=>Rez.Drawables.turkeyface,
	        	:locX=>xPos,
	        	:locY=>yPos
	        });
        
        turkeyIcon = WatchUi.loadResource(Rez.Drawables.turkeyicon);

        // If this device supports BufferedBitmap, allocate the buffers we use for drawing
        if(Toybox.Graphics has :BufferedBitmap) {
            // Allocate a full screen size buffer with a palette of only 4 colors to draw
            // the background image of the watchface.  This is used to facilitate blanking
            // the second hand during partial updates of the display
            offscreenBuffer = new Graphics.BufferedBitmap({
                :width=>dc.getWidth(),
                :height=>dc.getHeight(),
                :palette=> [
                    Graphics.COLOR_TRANSPARENT,
                    Graphics.COLOR_BLACK,
                    Graphics.COLOR_WHITE,
                    0xFF0000,
                    0xFFAA00,
                    0xAA5500
                ]
            });

            // Allocate a buffer tall enough to draw the date into the full width of the
            // screen. This buffer is also used for blanking the second hand. This full
            // color buffer is needed because anti-aliased fonts cannot be drawn into
            // a buffer with a reduced color palette
            turkeyBuffer = new Graphics.BufferedBitmap({
                :width=>150,
                :height=>150,
                :bitmapResource=>turkeyIcon
            });
        } else {
            turkeyBuffer = null;
        }

        curClip = null;

        screenCenterPoint = [dc.getWidth()/2, dc.getHeight()/2];
    }

    // This function is used to generate the coordinates of the 4 corners of the polygon
    // used to draw a watch hand. The coordinates are generated with specified length,
    // tail length, and width and rotated around the center point at the provided angle.
    // 0 degrees is at the 12 o'clock position, and increases in the clockwise direction.
    function generateHandCoordinates(centerPoint, angle, handLength, tailLength, width) {
        // Map out the coordinates of the watch hand
        var coords = [[-(width / 2), tailLength], [-(width / 2), -handLength], [width / 2, -handLength], [width / 2, tailLength]];
        var result = new [4];
        var cos = Math.cos(angle);
        var sin = Math.sin(angle);

        // Transform the coordinates
        for (var i = 0; i < 4; i += 1) {
            var x = (coords[i][0] * cos) - (coords[i][1] * sin) + 0.5;
            var y = (coords[i][0] * sin) + (coords[i][1] * cos) + 0.5;

            result[i] = [centerPoint[0] + x, centerPoint[1] + y];
        }

        return result;
    }

    // Draws the clock tick marks around the outside edges of the screen.
    function drawHashMarks(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();

        var sX, sY;
        var eX, eY;
        var outerRad = 30;
        var innerRad = outerRad - 3;
        dc.setColor(0x555500, Graphics.COLOR_TRANSPARENT);
        // Loop through each 15 minute block and draw tick marks.
        for (var i = 0; i <= 11 * Math.PI / 6; i += (Math.PI / 6)) {
            //won't be exact due to truncation
            if(i > 9 * Math.PI / 6 - 0.5 && i < 9 * Math.PI / 6 + 0.5) {
            	continue;
            }
            sY = dc.getHeight() / 2 + innerRad * Math.sin(i);
            eY = dc.getHeight() / 2 + outerRad * Math.sin(i);
            sX = dc.getWidth() / 2 + innerRad * Math.cos(i);
            eX = dc.getWidth() / 2 + outerRad * Math.cos(i);
            dc.setPenWidth(1);
            dc.drawLine(sX, sY, eX, eY);
        }
        
    }

    // Handle the update event
    function onUpdate(dc) {
        var width;
        var height;
        var screenWidth = dc.getWidth();
        var clockTime = System.getClockTime();
        var minuteHandAngle;
        var hourHandAngle;
        var secondHand;
        var hourHand;
        var targetDc = null;

        // We always want to refresh the full screen when we get a regular onUpdate call.
        fullScreenRefresh = true;

        // Fill the entire background with Black.
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        if(Toybox.Graphics.Dc has :clearClip) {
        	dc.clearClip();
        }
        dc.fillRectangle(0, 0, dc.getWidth(), dc.getHeight());
        
        drawDateString( dc, dc.getWidth() / 2, dc.getHeight() * 3 / 4 );
        
        if(null != turkeyBuffer) {
            dc.clearClip();
            curClip = null;
            // If we have an offscreen buffer that we are using to draw the background,
            // set the draw context of that buffer as our target.
            targetDc = dc;//turkeyBuffer.getDc();
        } else {
            targetDc = dc;
        }

        width = targetDc.getWidth();
        height = targetDc.getHeight();
        
        if( null != turkeyBuffer ) {
            var turkeyDc = turkeyBuffer.getDc();
        }
        
        // Output the offscreen buffers to the main display if required.
        drawBackground(dc);

        //block feathers
        //fully blocked: 54
        //fully exposed: 98
        //difference: 44
        var activityInfo = ActivityMonitor.getInfo();
        var blockerRadius = 97;
        if(activityInfo.steps != null && activityInfo.stepGoal != null && activityInfo.stepGoal != 0 && activityInfo.steps < activityInfo.stepGoal){
        	var stepMult = (activityInfo.steps + 0.0) / (activityInfo.stepGoal + 0.0);
        	blockerRadius = 54 + stepMult * 44;
        }
        dc.setPenWidth(44);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.drawArc(dc.getWidth() / 2, dc.getHeight() / 2, blockerRadius, dc.ARC_COUNTER_CLOCKWISE, -15, 196);
        if (null != backgroundTurkey) {
            backgroundTurkey.draw(dc);
        }

        onPartialUpdate( dc );

        fullScreenRefresh = false;
    }

    // Draw the date string into the provided buffer at the specified location
    function drawDateString( dc, x, y ) {
        var info = Gregorian.info(Time.now(), Time.FORMAT_LONG);
        var dateStr = Lang.format("$1$ $2$ $3$", [info.day_of_week, info.month, info.day]);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_MEDIUM, dateStr, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Handle the partial update event
    function onPartialUpdate( dc ) {
        if(disableSeconds && !fullScreenRefresh){
        	return;
        }
        
        var clockTime = System.getClockTime();
        var secondHand = (clockTime.sec / 60.0) * Math.PI * 2;
        var hourHand = (((clockTime.hour % 12) * 60) + clockTime.min);
        hourHand = hourHand / (12 * 60.0);
        hourHand = hourHand * Math.PI * 2;
        var minuteHand = (clockTime.min / 60.0) * Math.PI * 2;
        var secondHandPoints = generateHandCoordinates(screenCenterPoint, secondHand, 30, 10, 2);
        var minuteHandPoints = generateHandCoordinates(screenCenterPoint, minuteHand, 30, 0, 2);
        var hourHandPoints = generateHandCoordinates(screenCenterPoint, hourHand, 20, 0, 2);

        // Update the cliping rectangle to the new location of the second hand.
        var oldCurClip = curClip;
        curClip = getBoundingBox( secondHandPoints );
        if(!fullScreenRefresh) {
	        if(oldCurClip != null) {
	        	var bboxWidth = ((curClip[1][0] > oldCurClip[1][0]) ? curClip[1][0] : oldCurClip[1][0]) - ((curClip[0][0] < oldCurClip[0][0]) ? curClip[0][0] : oldCurClip[0][0]) + 1;
		        var bboxHeight = ((curClip[1][1] > oldCurClip[1][1]) ? curClip[1][1] : oldCurClip[1][1]) - ((curClip[0][1] < oldCurClip[0][1]) ? curClip[0][1] : oldCurClip[0][1]) + 1;
		        dc.setClip(((curClip[0][0] < oldCurClip[0][0]) ? curClip[0][0] : oldCurClip[0][0]), ((curClip[0][1] < oldCurClip[0][1]) ? curClip[0][1] : oldCurClip[0][1]), bboxWidth, bboxHeight);
		    }
		    else {
		    	var bboxWidth = curClip[1][0] - curClip[0][0] + 1;
		        var bboxHeight = curClip[1][1] - curClip[0][1] + 1;
		        dc.setClip(curClip[0][0], curClip[0][1], bboxWidth, bboxHeight);
		    }
	    }

        if(!fullScreenRefresh) {
            drawBackground(dc);
        }
        
        // Draw the tick marks around the edges of the screen
        drawHashMarks(dc);
        
        // Draw the hands to the screen.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(minuteHandPoints);
        dc.fillPolygon(hourHandPoints);
        if( !disableSeconds && ( partialUpdatesAllowed || isAwake ) ) {
	        dc.setColor(Graphics.COLOR_DK_GREEN, Graphics.COLOR_TRANSPARENT);
	        dc.fillPolygon(secondHandPoints);
        }

        // Draw the arbor in the center of the screen.
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_BLACK);
        dc.fillCircle(dc.getWidth() / 2, dc.getHeight() / 2, 3);
        dc.setColor(Graphics.COLOR_BLACK,Graphics.COLOR_BLACK);
        dc.drawCircle(dc.getWidth() / 2, dc.getHeight() / 2, 3);
    }

    // Compute a bounding box from the passed in points
    function getBoundingBox( points ) {
        var min = [9999,9999];
        var max = [0,0];

        for (var i = 0; i < points.size(); ++i) {
            if(points[i][0] < min[0]) {
                min[0] = points[i][0];
            }

            if(points[i][1] < min[1]) {
                min[1] = points[i][1];
            }

            if(points[i][0] > max[0]) {
                max[0] = points[i][0];
            }

            if(points[i][1] > max[1]) {
                max[1] = points[i][1];
            }
        }

        return [min, max];
    }

    // Draw the watch face background
    // onUpdate uses this method to transfer newly rendered Buffered Bitmaps
    // to the main display.
    // onPartialUpdate uses this to blank the second hand from the previous
    // second before outputing the new one.
    function drawBackground(dc) {
        var width = dc.getWidth();
        var height = dc.getHeight();

        //If we have a turkey buffer that has been written to
        //draw it to the screen.
        if( null != turkeyBuffer ) {
            dc.drawBitmap(width / 2 - 75, height / 2 - 75 - 20, turkeyBuffer);
        }
        else {
        	dc.drawBitmap(dc.getWidth() / 2 - 75, dc.getHeight() / 2 - 75 - 20, turkeyIcon);
        }
    }

    // This method is called when the device re-enters sleep mode.
    // Set the isAwake flag to let onUpdate know it should stop rendering the second hand.
    function onEnterSleep() {
        isAwake = false;
        WatchUi.requestUpdate();
    }

    // This method is called when the device exits sleep mode.
    // Set the isAwake flag to let onUpdate know it should render the second hand.
    function onExitSleep() {
        isAwake = true;
    }
    
    function onSettingsChanged() {
    	disableSeconds = Application.getApp().getProperty("disableSeconds");
    	Ui.requestUpdate();
    }
}

class AnalogDelegate extends WatchUi.WatchFaceDelegate {
    // The onPowerBudgetExceeded callback is called by the system if the
    // onPartialUpdate method exceeds the allowed power budget. If this occurs,
    // the system will stop invoking onPartialUpdate each second, so we set the
    // partialUpdatesAllowed flag here to let the rendering methods know they
    // should not be rendering a second hand.
    function onPowerBudgetExceeded(powerInfo) {
        System.println( "Average execution time: " + powerInfo.executionTimeAverage );
        System.println( "Allowed execution time: " + powerInfo.executionTimeLimit );
        partialUpdatesAllowed = false;
    }
}
