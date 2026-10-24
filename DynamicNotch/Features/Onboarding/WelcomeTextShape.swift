// WelcomeTextShape.swift
// DynamicNotch / Features / Onboarding / Views
//
// Native 120 FPS Metal-rendered vector bezier shape extracted from the original
// Lottie animation. Delivers Apple-grade cursive neon handwriting with zero dependencies.

import SwiftUI

struct WelcomeTextShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let minX: CGFloat = -189.44
        let minY: CGFloat = -48.74
        let boundsW: CGFloat = 384.32
        let boundsH: CGFloat = 87.59

        // Apple Precision Inset: prevents any stroke lineWidth or glow bloom from clipping
        let drawRect = rect.insetBy(dx: 4.0, dy: 4.0)

        let scale = min(drawRect.width / boundsW, drawRect.height / boundsH)
        let offsetX = drawRect.midX - (boundsW * scale) / 2.0
        let offsetY = drawRect.midY - (boundsH * scale) / 2.0

        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: offsetX + (x - minX) * scale,
                y: offsetY + (y - minY) * scale
            )
        }

        path.move(to: pt(-188.4520, -48.7370))
        path.addCurve(to: pt(-174.8800, 37.5340), control1: pt(-188.4520, -48.7370), control2: pt(-194.8760, 41.3410))
        path.addCurve(to: pt(-150.8610, -18.6840), control1: pt(-160.6040, 34.8150), control2: pt(-150.8610, -18.6840))
        path.addCurve(to: pt(-139.4130, 37.5890), control1: pt(-150.8610, -18.6840), control2: pt(-158.3080, 40.6710))
        path.addCurve(to: pt(-115.6050, -41.1530), control1: pt(-124.3350, 35.1290), control2: pt(-95.8630, -42.4430))
        path.addCurve(to: pt(-102.7470, 24.9640), control1: pt(-127.6710, -40.3650), control2: pt(-127.0030, 16.8790))
        path.addCurve(to: pt(-71.0620, 8.0400), control1: pt(-87.5000, 30.0470), control2: pt(-71.8280, 19.7840))
        path.addCurve(to: pt(-94.2110, 9.0610), control1: pt(-70.1790, -5.5020), control2: pt(-88.5510, -7.7900))
        path.addCurve(to: pt(-70.7300, 37.6770), control1: pt(-99.4150, 24.5560), control2: pt(-90.4150, 43.4180))
        path.addCurve(to: pt(-25.2530, -28.9820), control1: pt(-42.6300, 29.4820), control2: pt(-26.7050, -13.7310))
        path.addCurve(to: pt(-42.6150, -32.3010), control1: pt(-23.7210, -45.0670), control2: pt(-35.4660, -46.5990))
        path.addCurve(to: pt(-36.2320, 38.6780), control1: pt(-49.2930, -18.9450), control2: pt(-60.2820, 38.6780))
        path.addCurve(to: pt(-2.1480, 2.1780), control1: pt(-22.9700, 38.6780), control2: pt(-16.1170, 10.3830))
        path.addCurve(to: pt(14.5480, -2.0290), control1: pt(7.7700, -3.6470), control2: pt(14.5480, -2.0290))
        path.addCurve(to: pt(-12.7730, 17.6080), control1: pt(14.5480, -2.0290), control2: pt(-8.3240, -0.7300))
        path.addCurve(to: pt(15.0270, 35.6780), control1: pt(-14.9310, 26.5040), control2: pt(-5.8010, 46.5990))
        path.addCurve(to: pt(51.7080, -0.6990), control1: pt(34.3820, 25.5290), control2: pt(27.6060, 2.3760))
        path.addCurve(to: pt(67.3420, 18.3800), control1: pt(61.4880, -1.9460), control2: pt(67.9890, 9.9750))
        path.addCurve(to: pt(44.6190, 38.2950), control1: pt(66.4490, 29.9970), control2: pt(55.4700, 39.8270))
        path.addCurve(to: pt(32.2370, 14.4230), control1: pt(34.7070, 36.8960), control2: pt(28.3600, 22.8420))
        path.addCurve(to: pt(51.7080, -0.6990), control1: pt(38.3360, 1.1780), control2: pt(45.4910, -0.1900))
        path.addCurve(to: pt(79.1240, 17.6230), control1: pt(66.8530, -1.9380), control2: pt(71.0600, 18.6040))
        path.addCurve(to: pt(92.4180, 5.7640), control1: pt(87.0080, 16.6640), control2: pt(92.4180, 5.7640))
        path.addCurve(to: pt(86.6650, 37.3880), control1: pt(92.4180, 5.7640), control2: pt(86.6650, 37.3880))
        path.addCurve(to: pt(107.6650, 2.0700), control1: pt(86.6650, 37.3880), control2: pt(98.2190, 1.1900))
        path.addCurve(to: pt(112.3580, 29.3530), control1: pt(118.3940, 3.0700), control2: pt(112.3580, 29.3530))
        path.addCurve(to: pt(133.0770, 2.6350), control1: pt(112.3580, 29.3530), control2: pt(122.5750, 0.4350))
        path.addCurve(to: pt(138.4650, 37.2580), control1: pt(143.2410, 4.7640), control2: pt(127.4150, 31.7330))
        path.addCurve(to: pt(179.3610, 8.5540), control1: pt(150.8880, 43.4700), control2: pt(178.5950, 20.2990))
        path.addCurve(to: pt(156.2120, 9.5750), control1: pt(180.2450, -4.9880), control2: pt(161.8720, -7.2760))
        path.addCurve(to: pt(175.5870, 38.8380), control1: pt(151.6590, 23.1340), control2: pt(159.9880, 38.8030))
        path.addCurve(to: pt(194.8760, 31.7410), control1: pt(185.4650, 38.8600), control2: pt(192.8600, 33.3240))

        return path
    }
}
