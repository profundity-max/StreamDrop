import AppKit
let out=CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath:out,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
    let image=NSImage(size:NSSize(width:size,height:size))
    image.lockFocus()
    let s=CGFloat(size)
    let rect=NSRect(x:s*0.06,y:s*0.06,width:s*0.88,height:s*0.88)
    let path=NSBezierPath(roundedRect:rect,xRadius:s*0.21,yRadius:s*0.21)
    NSGradient(starting:NSColor(calibratedRed:0.70,green:0.48,blue:0.94,alpha:1),ending:NSColor(calibratedRed:0.35,green:0.33,blue:0.76,alpha:1))!.draw(in:path,angle:-60)
    let tray=NSBezierPath();tray.lineWidth=s*0.055;tray.lineCapStyle = .round;tray.lineJoinStyle = .round
    tray.move(to:NSPoint(x:s*0.28,y:s*0.39));tray.line(to:NSPoint(x:s*0.28,y:s*0.28));tray.line(to:NSPoint(x:s*0.72,y:s*0.28));tray.line(to:NSPoint(x:s*0.72,y:s*0.39));NSColor.white.setStroke();tray.stroke()
    let arrow=NSBezierPath();arrow.lineWidth=s*0.06;arrow.lineCapStyle = .round;arrow.lineJoinStyle = .round
    arrow.move(to:NSPoint(x:s*0.5,y:s*0.73));arrow.line(to:NSPoint(x:s*0.5,y:s*0.43));arrow.move(to:NSPoint(x:s*0.38,y:s*0.54));arrow.line(to:NSPoint(x:s*0.5,y:s*0.42));arrow.line(to:NSPoint(x:s*0.62,y:s*0.54));arrow.stroke()
    image.unlockFocus()
    let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!
    let data=rep.representation(using:.png,properties:[:])!
    // Logical sizes and @2x variants required by iconutil.
    if [16,32,128,256,512].contains(size) {try data.write(to:URL(fileURLWithPath:out+"/icon_\(size)x\(size).png"))}
    if [32,64,256,512,1024].contains(size) {let half=size/2;try data.write(to:URL(fileURLWithPath:out+"/icon_\(half)x\(half)@2x.png"))}
}
