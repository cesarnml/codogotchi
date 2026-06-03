import Foundation

/// First-launch bootstrap: ensure `~/.codogotchi/config.json` exists with a
/// minimal Lite config. Coordinates with P5.04 pet seed order so the first
/// frame can show Maew without `codogotchi setup`.
enum ConfigBootstrap {
	enum Outcome: Equatable {
		case wrote
		case alreadyExists
	}

	enum Failure: Error {
		case writeFailed(underlying: Error)
	}

	/// Writes the minimal Lite config when missing. Does not overwrite an
	/// existing config — Outcome `.alreadyExists` signals no-op.
	///
	/// Implementation: a `fileExists` fast path avoids serializing JSON when
	/// the file is already there, but the write itself uses
	/// `[.atomic, .withoutOverwriting]` so the existence check and write are
	/// TOCTOU-safe — if `config.json` appears in the race window between the
	/// check and the rename, the write fails with `NSFileWriteFileExistsError`
	/// and we treat it as `.alreadyExists` instead of clobbering the new file.
	@discardableResult
	static func ensureLiteConfig() throws -> Outcome {
		let url = PetConfig.configURL()
		if FileManager.default.fileExists(atPath: url.path) {
			return .alreadyExists
		}

		let payload: [String: Any] = [
			"profile_id": UUID().uuidString,
			"pet": DEFAULT_PET_NAME,
			"features": ["rpg_enabled": true, "rpg_hud_enabled": true],
		]

		do {
			try FileManager.default.createDirectory(
				at: url.deletingLastPathComponent(),
				withIntermediateDirectories: true
			)
			let data = try JSONSerialization.data(
				withJSONObject: payload,
				options: [.prettyPrinted, .sortedKeys]
			)
			return try writeExclusive(data: data, to: url)
		} catch let failure as Failure {
			throw failure
		} catch {
			throw Failure.writeFailed(underlying: error)
		}
	}

	/// Exclusive-create + write. Uses `open(2)` with `O_WRONLY | O_CREAT | O_EXCL`
	/// so we cannot clobber a file that appeared after our `fileExists` check.
	/// Returns `.alreadyExists` if `EEXIST` was the failure mode; throws
	/// `Failure.writeFailed` for any other errno.
	private static func writeExclusive(data: Data, to url: URL) throws -> Outcome {
		let fd = url.withUnsafeFileSystemRepresentation { cPath -> Int32 in
			guard let cPath else { return -1 }
			return open(cPath, O_WRONLY | O_CREAT | O_EXCL, 0o600)
		}
		guard fd >= 0 else {
			let savedErrno = errno
			if savedErrno == EEXIST { return .alreadyExists }
			throw Failure.writeFailed(
				underlying: NSError(domain: NSPOSIXErrorDomain, code: Int(savedErrno))
			)
		}
		defer { close(fd) }

		var written = 0
		while written < data.count {
			let remaining = data.count - written
			let n = data.withUnsafeBytes { raw -> Int in
				guard let base = raw.baseAddress else { return -1 }
				return write(fd, base.advanced(by: written), remaining)
			}
			if n < 0 {
				if errno == EINTR { continue }
				throw Failure.writeFailed(
					underlying: NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
				)
			}
			if n == 0 { break }
			written += n
		}
		return .wrote
	}
}
