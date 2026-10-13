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
            // Fast path: Aftermath writes UTC timestamps as yyyy-MM-ddTHH:mm:ss[Z];
            // read the fields directly instead of running a date parser on every row.
            let b = Array(raw.utf8)
            if b.count >= 19, b[4] == 45, b[7] == 45, b[10] == 84, b[13] == 58, b[16] == 58,
               b.count == 19 || (b.count == 20 && b[19] == 90) {
                func num(_ r: Range<Int>) -> Int? {
                    var v = 0
                    for i in r { guard b[i] >= 48 && b[i] <= 57 else { return nil }; v = v * 10 + Int(b[i] - 48) }
                    return v
                }
                if let y = num(0..<4), let mo = num(5..<7), let d = num(8..<10),
                   let h = num(11..<13), let mi = num(14..<16), let s = num(17..<19),
                   (1...12).contains(mo), (1...31).contains(d), h < 24, mi < 60, s < 61 {
                    // Days since 1970-01-01 (proleptic Gregorian, UTC)
                    let yy = mo <= 2 ? y - 1 : y
                    let era = (yy >= 0 ? yy : yy - 399) / 400
                    let yoe = yy - era * 400
                    let doy = (153 * (mo + (mo > 2 ? -3 : 9)) + 2) / 5 + d - 1
                    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
                    let days = era * 146097 + doe - 719468
                    return Date(timeIntervalSince1970: TimeInterval(days * 86400 + h * 3600 + mi * 60 + s))
                }
            }
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
