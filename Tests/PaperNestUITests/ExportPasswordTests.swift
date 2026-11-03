import Foundation
import Testing
import PaperNestExport
@testable import PaperNestUI

/// Protecting an exported PDF with a password.
///
/// The engine has taken a password since 2026-10-27, with three careful
/// refusals, and nothing could set one. The refusals are the interesting
/// part: a password the writer cannot store must be explained where it is
/// typed, not thrown back as "export failed" after the fact. That is what
/// the engine's own comment asks of whoever builds the screen.
@Suite struct ExportPasswordTests {
    /// Only a PDF can carry one. Writing an unprotected JPEG when someone
    /// asked for protection is a silent false promise, so the field is not
    /// offered at all for the rest.
    @Test func onlyAPDFCanCarryAPassword() {
        for format in ExportFormat.allCases {
            #expect(format.canCarryPassword == (format == .pdf), "\(format)")
        }
    }

    /// An empty field means **no password**, not an empty one. The engine
    /// refuses `""` outright, because written as both the user and the owner
    /// password it produces a file that opens with nothing while the caller
    /// believes it is protected — and an untouched text field is the most
    /// likely source of exactly that value.
    @Test func anEmptyFieldMeansNoPasswordAtAll() {
        #expect(ExportSheet.passwordToUse("") == nil)
        #expect(ExportSheet.passwordProblem(in: "", format: .pdf) == nil)
    }

    @Test func anOrdinaryPasswordIsUsedAsTyped() {
        #expect(ExportSheet.passwordToUse("Quarterly-2026") == "Quarterly-2026")
        #expect(ExportSheet.passwordProblem(in: "Quarterly-2026", format: .pdf) == nil)
    }

    /// Measured, not inferred: the writer refused `"été-Ñandú-2026"` as well
    /// as `"contraseña-密码-1"`, so Latin-1 is not the boundary. This is a
    /// real limitation for French and Spanish readers and the screen has to
    /// say so rather than reject their password with a generic error.
    @Test func aPasswordTheWriterCannotStoreIsCaughtBeforeExporting() {
        for password in ["été-Ñandú-2026", "contraseña-密码-1", "naïve", "pass—word"] {
            #expect(ExportSheet.passwordProblem(in: password, format: .pdf) == .passwordNotRepresentable,
                    "\(password) should be refused where it is typed")
        }
    }

    /// Offering the field only for PDF is the first guard; this is the
    /// second, in case a format is switched after a password is typed.
    @Test func aPasswordOnAFormatThatCannotCarryOneIsRefused() {
        for format in ExportFormat.allCases where format != .pdf {
            #expect(ExportSheet.passwordProblem(in: "secret", format: format) == .passwordNotSupported,
                    "\(format)")
        }
    }

    /// Revision 4 honours only the first 32 bytes. The whole password still
    /// opens the file, so this is not a refusal — but someone typing a long
    /// passphrase believes all of it is protecting them, and it is not.
    @Test func aPasswordLongerThanThirtyTwoBytesIsFlaggedButAllowed() {
        let long = String(repeating: "a", count: 33)
        let fits = String(repeating: "a", count: 32)

        #expect(ExportSheet.passwordIsTruncated(long))
        #expect(!ExportSheet.passwordIsTruncated(fits))
        // Allowed: it still opens the file.
        #expect(ExportSheet.passwordProblem(in: long, format: .pdf) == nil)
    }

    /// Counted in bytes, because that is what the limit is in. A password of
    /// 32 characters that are two bytes each is over it — unreachable today
    /// since those characters are refused anyway, but the two rules must not
    /// quietly disagree if that ever changes.
    @Test func theLimitIsCountedInBytesNotCharacters() {
        #expect(ExportSheet.passwordIsTruncated(String(repeating: "é", count: 20)))
    }
}
