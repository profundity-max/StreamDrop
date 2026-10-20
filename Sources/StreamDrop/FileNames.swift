import Foundation
import Darwin

/// Final names belong here; temporary transfer names are not user filenames.
enum FileNames {
    static func available(_ name:String,in directory:URL)throws -> URL {
        let limit=pathconf(directory.path,_PC_NAME_MAX)
        guard limit>0 else{throw InputError.invalid("无法确认保存目录的文件名长度限制。")}
        // Use a conservative UTF-8 budget even on filesystems that count UTF-16
        // units. Reserve the extension and collision suffix before shortening.
        let budget=min(Int(limit),255)
        let bad=CharacterSet.controlCharacters.union(CharacterSet(charactersIn:":/\\"))
        let leaf=(name as NSString).lastPathComponent.components(separatedBy:bad).joined(separator:"_").trimmingCharacters(in:.whitespacesAndNewlines)
        let clean=leaf.isEmpty || leaf=="." || leaf==".." ? "download" : leaf
        let ext=(clean as NSString).pathExtension
        let ending=ext.isEmpty ? "" : "."+ext
        let base=(clean as NSString).deletingPathExtension
        guard ending.utf8.count<budget else{throw InputError.invalid("文件扩展名过长，无法安全保存。")}
        var number=1
        while true {
            let suffix=number==1 ? "" : " (\(number))"
            let remaining=budget-ending.utf8.count-suffix.utf8.count
            var stem="",used=0
            for character in base {
                let width=String(character).utf8.count
                guard used+width<=remaining else{break}
                stem.append(character);used+=width
            }
            if stem.isEmpty{stem="download"}
            guard stem.utf8.count<=remaining else{throw InputError.invalid("文件名没有足够空间保留扩展名和同名编号。")}
            let candidate=directory.appendingPathComponent(stem+suffix+ending)
            if !FileManager.default.fileExists(atPath:candidate.path){return candidate}
            number+=1
        }
    }
}
