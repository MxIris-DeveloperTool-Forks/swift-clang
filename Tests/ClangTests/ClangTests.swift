import XCTest
@testable import CclangWrapper
@testable import Clang

func testFile(for filename: String) -> String {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("input_tests")
        .appendingPathComponent(filename)
        .path
}

class ClangTests: XCTestCase {
    func testInitTranslationUnitUsingArguments() {
        do {
            let unit = try TranslationUnit(clangSource: "int main(void) {int a; return 0;}",
                                           language: .c,
                                           commandLineArgs: ["-Wall"])
            XCTAssertEqual(unit.diagnostics.map { $0.description },
                           ["unused variable \'a\'"])
        } catch {
            XCTFail("\(error)")
        }
    }

    func testInitUsingStringAsSource() {
        do {
            let unit = try TranslationUnit(clangSource: "int main() {}", language: .c)
            let lexems =
                unit.tokens(in: unit.cursor.range).map { $0.spelling(in: unit) }
            XCTAssertEqual(lexems, ["int", "main", "(", ")", "{", "}"])
        } catch {
            XCTFail("\(error)")
        }
    }

    func testDiagnostic() {
        do {
            let src = "void main() {int a = \"\"; return 0}"
            let unit = try TranslationUnit(clangSource: src, language: .c)
            let diagnostics = unit.diagnostics
            XCTAssertEqual(diagnostics.count, 4)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testUnsavedFile() {
        let unsavedFile = UnsavedFile(filename: "a.c", contents: "void f(void);")

        XCTAssertEqual(unsavedFile.filename, "a.c")
        XCTAssertTrue(strcmp(unsavedFile.clang.Filename, "a.c") == 0)

        XCTAssertEqual(unsavedFile.contents, "void f(void);")
        XCTAssertTrue(strcmp(unsavedFile.clang.Contents, "void f(void);") == 0)
        XCTAssertEqual(unsavedFile.clang.Length, 13)

        unsavedFile.filename = "b.c"
        XCTAssertEqual(unsavedFile.filename, "b.c")
        XCTAssertTrue(strcmp(unsavedFile.clang.Filename, "b.c") == 0)

        unsavedFile.contents = "int add(int, int);"
        XCTAssertEqual(unsavedFile.contents, "int add(int, int);")
        XCTAssertTrue(strcmp(unsavedFile.clang.Contents, "int add(int, int);") == 0)
        XCTAssertEqual(unsavedFile.clang.Length, 18)
    }

    func testTUReparsing() {
        do {
            let filename = testFile(for: "reparse.c")
            let index = Index()
            let unit = try TranslationUnit(filename: filename, index: index)

            let src = "int add(int, int);"
            let unsavedFile = UnsavedFile(filename: filename, contents: src)

            try unit.reparseTransaltionUnit(using: [unsavedFile],
                                            options: unit.defaultReparseOptions)

            XCTAssertEqual(
                unit.tokens(in: unit.cursor.range).map { $0.spelling(in: unit) },
                ["int", "add", "(", "int", ",", "int", ")", ";"]
            )
        } catch {
            XCTFail("\(error)")
        }
    }

    func testInitFromASTFile() {
        do {
            let filename = testFile(for: "init-ast.c")
            let astFilename = "/tmp/JKN-23-AC.ast"

            let unit = try TranslationUnit(filename: filename)
            try unit.saveTranslationUnit(in: astFilename,
                                         withOptions: unit.defaultSaveOptions)
            defer {
                try? FileManager.default.removeItem(atPath: astFilename)
            }

            let unit2 = try TranslationUnit(astFilename: astFilename)
            XCTAssertEqual(
                unit2.tokens(in: unit2.cursor.range).map { $0.spelling(in: unit2) },
                ["int", "main", "(", "void", ")", "{", "return", "0", ";", "}"]
            )
        } catch {
            XCTFail("\(error)")
        }
    }

    func testLocationInitFromLineAndColumn() {
        do {
            let filename = testFile(for: "locations.c")
            let unit = try TranslationUnit(filename: filename)
            let file = File(clang: CclangWrapper.clang_getFile(unit.clang, filename)!)

            let start =
                SourceLocation(translationUnit: unit, file: file, line: 2, column: 3)
            let end =
                SourceLocation(translationUnit: unit, file: file, line: 4, column: 17)
            let range = SourceRange(start: start, end: end)

            XCTAssertEqual(
                unit.tokens(in: range).map { $0.spelling(in: unit) },
                ["int", "a", "=", "1", ";", "int", "b", "=", "1", ";", "int", "c", "=",
                 "a", "+", "b", ";"]
            )
        } catch {
            XCTFail("\(error)")
        }
    }

    func testLocationInitFromOffset() {
        do {
            let filename = testFile(for: "locations.c")
            let unit = try TranslationUnit(filename: filename)
            let file = unit.getFile(for: unit.spelling)!

            let start = SourceLocation(translationUnit: unit, file: file, offset: 19)
            let end = SourceLocation(translationUnit: unit, file: file, offset: 59)
            let range = SourceRange(start: start, end: end)

            XCTAssertEqual(
                unit.tokens(in: range).map { $0.spelling(in: unit) },
                ["int", "a", "=", "1", ";", "int", "b", "=", "1", ";", "int", "c", "=",
                 "a", "+", "b", ";"]
            )
        } catch {
            XCTFail("\(error)")
        }
    }

    func testIndexAction() {
        do {
            let filename = testFile(for: "index-action.c")
            let unit = try TranslationUnit(filename: filename)

            let indexerCallbacks = Clang.IndexerCallbacks()
            var functionsFound = Set<String>()
            indexerCallbacks.indexDeclaration = { decl in
                if decl.cursor is FunctionDecl {
                    functionsFound.insert(decl.cursor!.description)
                }
            }

            try unit.indexTranslationUnit(indexAction: IndexAction(),
                                          indexerCallbacks: indexerCallbacks,
                                          options: .none)

            XCTAssertEqual(functionsFound,
                           Set<String>(arrayLiteral: "main", "didLaunch"))
        } catch {
            XCTFail("\(error)")
        }
    }

    func testParsingWithUnsavedFile() {
        do {
            let filename = testFile(for: "unsaved-file.c")
            let src = "int main(void) { return 0; }"
            let unsavedFile = UnsavedFile(filename: filename, contents: src)
            let unit = try TranslationUnit(filename: filename,
                                           unsavedFiles: [unsavedFile])

            XCTAssertEqual(
                unit.tokens(in: unit.cursor.range).map { $0.spelling(in: unit) },
                ["int", "main", "(", "void", ")", "{", "return", "0", ";", "}"]
            )
        } catch {
            XCTFail("\(error)")
        }
    }

    func testIsFromMainFile() {
        do {
            let unit = try TranslationUnit(filename: testFile(for: "is-from-main-file.c"))

            var functions = [Cursor]()
            unit.visitChildren { cursor in
                if cursor is FunctionDecl, cursor.range.start.isFromMainFile {
                    functions.append(cursor)
                }
                return .recurse
            }

            XCTAssertEqual(functions.map { $0.description }, ["main"])
        } catch {
            XCTFail("\(error)")
        }
    }

    func testVisitInclusion() {
        func fileName(_ file: File) -> String {
            return file.name.components(separatedBy: "/").last!
        }
        do {
            let inclusionEx = [
                ["inclusion.c"],
                ["inclusion-header.h", "inclusion.c"],
            ]
            let unit = try TranslationUnit(filename: testFile(for: "inclusion.c"))
            var inclusion: [[String]] = []
            unit.visitInclusion { file, stack in
                let inc = [fileName(file)] + stack.map { fileName($0.file) }
                inclusion.append(inc)
            }
            XCTAssertEqual(inclusion, inclusionEx)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testGetFile() {
        do {
            let fileName = testFile(for: "init-ast.c")
            let unit = try TranslationUnit(filename: fileName)
            XCTAssertNotNil(unit.getFile(for: fileName))
            XCTAssertNil(unit.getFile(for: "42"))
        } catch {
            XCTFail("\(error)")
        }
    }

    func testDisposeTranslateUnit() {
        do {
            let filename = testFile(for: "init-ast.c")
            let unit = try TranslationUnit(filename: filename)
            let cursor = unit.cursor
            for _ in 0 ..< 2 {
                _ = cursor.translationUnit
            }
        } catch {
            XCTFail("\(error)")
        }
    }

    func testSwiftNameMacro() {
        do {
            let filename = testFile(for: "swiftname.m")
            let unit = try TranslationUnit(filename: filename, commandLineArgs: [
                "-isysroot", 
                "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk",
                "-F/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks",
                "-x", "objective-c",
                "-fmodules",
            ], options: [.detailedPreprocessingRecord])
            unit.cursor.visitChildren { cursor in
                guard cursor.range.end.isFromMainFile else { return .recurse }
                for token in unit.tokens(in: cursor.range) {
                    print(token.spelling(in: unit))
                }
//                print(cursor.children())
                return .recurse
            }
        } catch {
            XCTFail("\(error)")
        }
    }

    static var allTests: [(String, (ClangTests) -> () throws -> Void)] {
        return [
            ("testInitUsingStringAsSource", testInitUsingStringAsSource),
            ("testDiagnostic", testDiagnostic),
            ("testUnsavedFile", testUnsavedFile),
            ("testInitFromASTFile", testInitFromASTFile),
            ("testLocationInitFromLineAndColumn", testLocationInitFromLineAndColumn),
            ("testLocationInitFromOffset", testLocationInitFromOffset),
            ("testIndexAction", testIndexAction),
            ("testParsingWithUnsavedFile", testParsingWithUnsavedFile),
            ("testIsFromMainFile", testIsFromMainFile),
            ("testVisitInclusion", testVisitInclusion),
            ("testGetFile", testGetFile),
        ]
    }
}
