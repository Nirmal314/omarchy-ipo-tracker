import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: root
  property real iconSize: Style.font.icon
  property color color: Color.foreground
  readonly property real viewBox: 24
  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize
  Item {
    anchors.centerIn: parent
    width: root.viewBox
    height: root.viewBox
    scale: Math.min(root.width, root.height) / root.viewBox
    Shape {
      anchors.fill: parent
      antialiasing: true
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        strokeColor: root.color
        strokeWidth: 2
        fillColor: "transparent"
        strokeStyle: ShapePath.SolidLine
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: "M3 3v16a2 2 0 0 0 2 2h16" }
      }
      ShapePath {
        strokeColor: root.color
        strokeWidth: 2
        fillColor: "transparent"
        strokeStyle: ShapePath.SolidLine
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: "m19 9-5 5-4-4-3 3" }
      }
    }
  }
}
