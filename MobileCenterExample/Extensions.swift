//
//  Extensions.swift
//  MobileCenterExample
//
//  Created by nypreHeB on 10.05.17.
//  Copyright © 2017 Akvelon. All rights reserved.
//

import Foundation

extension ClosedRange where Bound : FloatingPoint {
    public func random() -> Bound {
        let range = self.upperBound - self.lowerBound
        let randomValue = (Bound(arc4random_uniform(UINT32_MAX)) / Bound(UINT32_MAX)) * range + self.lowerBound
        return randomValue
    }
}

extension Date {
    var startOfDay: Date {
        return Calendar.current.startOfDay( for: self )
    }
    
    var endOfDay: Date? {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date( byAdding: components, to: startOfDay )
    }
}
