//
//  MainTabBarController.swift
//  MobileCenterExample
//
//  Created by nypreHeB on 10.05.17.
//  Copyright © 2017 Akvelon. All rights reserved.
//

import UIKit
import HealthKit
import MobileCenterAnalytics

class MainTabBarController: UITabBarController, UITabBarControllerDelegate {

    var healthStore = HKHealthStore()
    var userStats = TimedData<UserStats>()
    var operationsCounter = Int()
    var needGenerateData = [Int: Bool]()
    var triedToGenerateData = false
    
    
    let actualTypes = [HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.stepCount)!,
                       HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.distanceWalkingRunning)!,
                       HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.activeEnergyBurned)!,
                       HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.appleExerciseTime)!]
    
    public var user: User? {
        didSet {
            (self.childViewControllers.first as! ProfilePageViewController).user = user
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.delegate = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear( animated )
        if !triedToGenerateData {
            triedToGenerateData = false
            self.checkNeedGenerateHealthKitData()
        }
    }
    
    func updateContent() {
        (self.childViewControllers.first as! ProfilePageViewController).userStats = userStats
        (self.childViewControllers.last as! StatisticsViewController).userStats = userStats
    }
    
    func increaseOperationsCounter() -> Void {
        objc_sync_enter( operationsCounter )
        operationsCounter += 1
        objc_sync_exit( operationsCounter )
    }
    
    func decreaseOperationsCounter() -> Void {
        objc_sync_enter( operationsCounter )
        operationsCounter -= 1
        if operationsCounter == 0 {
            
            var needGenerate = false
            for (_, value) in needGenerateData {
                if ( value ) {
                    needGenerate = true
                    break
                }
            }
            
            if needGenerate {
                //fillRandomData()
            }
            else {
                DispatchQueue.main.async() {
                    self.updateContent()
                    }
            }
            
        }
        objc_sync_exit( operationsCounter )
    }
    
    func querySample( type: HKQuantityType, for days: Int ) -> Void {
        
        increaseOperationsCounter()
        
        let calendar = Calendar.current
        var interval = DateComponents()
        interval.day = 1
        
        guard let anchorDate = Date().endOfDay else {
            fatalError("*** unable to create a valid date from the given components ***")
        }
        
        let query = HKStatisticsCollectionQuery(quantityType: type,
                                                quantitySamplePredicate: nil,
                                                options: .cumulativeSum,
                                                anchorDate: anchorDate,
                                                intervalComponents: interval)
        
        query.initialResultsHandler = {
            query, results, error in
            
            guard let statsCollection = results else {
                fatalError("*** An error occurred while calculating the statistics: \(String(describing: error?.localizedDescription)) ***")
            }
            
            var startDateComponents = DateComponents()
            startDateComponents.day = -days
            guard let startDate = calendar.date( byAdding: startDateComponents, to: anchorDate )?.endOfDay else {
                fatalError()
            }
            
            var unit: HKUnit
            switch type.identifier {
            case HKQuantityTypeIdentifier.stepCount.rawValue:
                unit = HKUnit.count()
            case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
                unit = HKUnit.meterUnit(with: HKMetricPrefix.kilo)
            case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
                unit = HKUnit.kilocalorie()
            case HKQuantityTypeIdentifier.appleExerciseTime.rawValue:
                unit = HKUnit.minute()
            default:
                fatalError( "unsupported HKQuantityTypeIdentifier" )
            }
            
            statsCollection.enumerateStatistics(from: startDate, to: anchorDate, with:{
                ( statistics, stop ) in
                if let quantity = statistics.sumQuantity() {
                    
                    let date = statistics.startDate
                    let value = quantity.doubleValue( for: unit )
                    
                    let difference = calendar.dateComponents( [.day, .hour], from: startDate, to: date )
                    guard let day = difference.day else {
                        fatalError()
                    }
                    let dayIndex = days - day - 1
                    self.needGenerateData[dayIndex] = false
                    
                    self.writeHealthKitData( for: dayIndex, and: type, value: value )
                }
            })
            
            self.decreaseOperationsCounter()
        }
        
        healthStore.execute( query )
    }
    
    func loadHealthKitData() -> Void {
        let readTypes = Set( actualTypes )
        
        healthStore.requestAuthorization(toShare: [], read: readTypes ) { ( result, error ) in
            if ( error == nil )
            {
                for readType in readTypes {
                    self.querySample( type: readType, for: 5 )
                }
            }
        }
    }
    
    func writeHealthKitData( for day: Int, and type: HKQuantityType, value: Double ) -> Void {
        self.userStats.getOrCreate(for: day)[type.identifier] = value
    }
    
    
    func generateRandomSample( from: Date, to: Date, identifier: HKQuantityTypeIdentifier ) -> HKQuantitySample {
        var unit: HKUnit
        switch identifier {
        case HKQuantityTypeIdentifier.stepCount:
            unit = HKUnit.count()
        case HKQuantityTypeIdentifier.distanceWalkingRunning:
            unit = HKUnit.meterUnit(with: HKMetricPrefix.kilo)
        case HKQuantityTypeIdentifier.activeEnergyBurned:
            unit = HKUnit.kilocalorie()
        case HKQuantityTypeIdentifier.appleExerciseTime:
            unit = HKUnit.minute()
        default:
            fatalError()
        }
        
        let value = (0...60).random()
        let quantity = HKQuantity(unit: unit, doubleValue: value)
        let type = HKSampleType.quantityType(forIdentifier: identifier)!
        
        let sample = HKQuantitySample(type: type, quantity: quantity, start: from, end: to)
        
        return sample
    }
    
    func fillRandomData() {
        var days = [Int]()
        for (day, value) in needGenerateData {
            if ( value ) {
                days.append(day)
            }
        }
        if ( days.count == 0 ) {
            return;
        }
        
        needGenerateData.removeAll()
        
        let now = Date()
        let calendar = NSCalendar.current
        var samples = [HKQuantitySample]()
        
        for day in days {
            let hoursDiff = day * 24
            for hour in 0...24  {
                let endDate = calendar.date(byAdding: .hour, value: -hour - hoursDiff, to: now)!
                let startDate = calendar.date(byAdding: .hour, value: -hour - 1 - hoursDiff, to: now)!
                
                samples.append(generateRandomSample(from: startDate, to: endDate, identifier: HKQuantityTypeIdentifier.stepCount))
                samples.append(generateRandomSample(from: startDate, to: endDate, identifier: HKQuantityTypeIdentifier.distanceWalkingRunning))
                samples.append(generateRandomSample(from: startDate, to: endDate, identifier: HKQuantityTypeIdentifier.activeEnergyBurned))
            }
        }

        /*healthStore.save( samples ) { ( completed, error ) in
            if let error = error {
                print( "error: ", error )
            }
            else {
                self.loadHealthKitData()
            }
        }*/
    }
    
    func checkNeedGenerateHealthKitData() {
        var readTypes = Set<HKQuantityType>()
        var writeTypes = Set<HKSampleType>()
        
        writeTypes.insert( HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.stepCount)! )
        writeTypes.insert( HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.distanceWalkingRunning)! )
        writeTypes.insert( HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.activeEnergyBurned)! )
        
        readTypes.insert( HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.stepCount)! )
        readTypes.insert( HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.distanceWalkingRunning)! )
        readTypes.insert( HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.activeEnergyBurned)! )
        readTypes.insert( HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.appleExerciseTime)! )
        
        #if (arch(i386) || arch(x86_64)) && os(iOS)
            for i in 0...4 {
                needGenerateData[i] = true
            }
        #endif
        
        healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { ( success, error ) in
            if ( success ) {
                MSAnalytics.trackEvent("Trying to retrieve data from HealthKit", withProperties: ["Page": "Main",
                                                                                                  "Category": "Request",
                                                                                                  "API": "HealthKit",
                                                                                                  "Result": "true"])
                self.loadHealthKitData()
            }
            else {
                if let error = error {
                    MSAnalytics.trackEvent("Trying to retrieve data from HealthKit", withProperties: ["Page": "Main",
                                                                                                      "Category": "Request",
                                                                                                      "API": "HealthKit",
                                                                                                      "Result": "false",
                                                                                                      "Error message": error.localizedDescription])
                }
                else {
                    MSAnalytics.trackEvent("Trying to retrieve data from HealthKit", withProperties: ["Page": "Main",
                                                                                                      "Category": "Request",
                                                                                                      "API": "HealthKit",
                                                                                                      "Result": "false",
                                                                                                      "Error message": "Unknown error"])
                }
            }
        }
    }
    
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        let index = self.viewControllers?.index(of: viewController)
        if index == 0 {
            MSAnalytics.trackEvent("View statistics button clicked", withProperties: ["Page": "Main",
                                                                                      "Category": "Clicks"])
        }
        else if index == 1 {
            MSAnalytics.trackEvent("View home button clicked", withProperties: ["Page": "Main",
                                                                                "Category": "Clicks"])
        }
        
    }
}
