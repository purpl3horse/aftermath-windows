//
//  Aftermath.swift
//  aftermath
//
//  Copyright  2022 JAMF Software, LLC


import Foundation

class Aftermath {

    static var fm: FileManager = .default

    //function for calling bash commands
    static func shell(_ command: String) -> String {
        let task = Process()
        let pipe = Pipe()

        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/bash"
        task.launch()

        let timerSource = DispatchSource.makeTimerSource()
        timerSource.setEventHandler {
            task.terminate()
        }
        timerSource.schedule(wallDeadline: .now() + 30)
        timerSource.resume()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)!
        
        return output
    }
    
    static func getPlistAsDict(atUrl: URL) -> [String: Any] {
        var data = Data()
        var plistDict = [String:Any]()
        
        if fm.fileExists(atPath: atUrl.relativePath) {
            do {
                data = try Data(contentsOf: atUrl)
                plistDict = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String:Any]
            } catch {
                print("Could not read \(atUrl.relativePath) due to \(error)")
            }
        }
        
        return plistDict
    }
    
    static func dateFromEpochTimestamp(timeStamp: Double) -> String {
        let date = NSDate(timeIntervalSince1970: timeStamp)
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        let dateString = dateFormatter.string(from: date as Date)
        return dateString
    }
    
    static func standardizeMetadataTimestamp(timeStamp: String) -> String {
        // yyyy-MM-dd'T'HH:mm:ss
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US")
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z" //"yyyy-MM-dd HH:mm:ss Z"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        if let date = dateFormatter.date(from: timeStamp) {
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            let dateString = dateFormatter.string(from: date as Date)
            return dateString
        }
            
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        if let date = dateFormatter.date(from: timeStamp) {
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            let dateString = dateFormatter.string(from: date as Date)
            return dateString
        } else {
            return "unknown"
        }
        
    }
    
    @available(macOS 12.0, *)
    static func sortCSV(unsortedArr: [[String]]) throws -> [[String]] {
        // Sorts rows newest first by the timestamp in their first column.
        // Timestamps appear both with and without a trailing "Z"; rows whose first column
        // isn't a timestamp (headers, "unknown") keep their order and go to the end.
        // (The previous comparator's guard was inverted, so rows were never reordered.)
        func parse(_ row: [String]) -> Date? {
            guard let raw = row.first?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
            let iso = raw.hasSuffix("Z") ? raw : "\(raw)Z"
            return try? Date(iso, strategy: .iso8601)
        }
        let keyed = unsortedArr.enumerated().map { (index: $0.offset, date: parse($0.element), row: $0.element) }
        let sorted = keyed.sorted { lhs, rhs in
            switch (lhs.date, rhs.date) {
            case let (l?, r?): return l != r ? l > r : lhs.index < rhs.index
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.index < rhs.index
            }
        }
        return sorted.map { $0.row }
    }
}
