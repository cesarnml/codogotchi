import AppKit

/// Width math shared by the attention bubble and subtitle truncation.
enum AttentionBubbleLayoutMetrics {
	static let minBubbleWidth: CGFloat = 200
	static let maxBubbleWidth: CGFloat = 280
	static let horizontalPadding: CGFloat = 10

	static func bubbleWidth(forPetWidth petWidth: CGFloat) -> CGFloat {
		max(minBubbleWidth, min(maxBubbleWidth, petWidth + 40))
	}

	static func subtitleContentWidth(forBubbleWidth bubbleWidth: CGFloat) -> CGFloat {
		bubbleWidth - horizontalPadding * 2
	}

	static func subtitleContentWidth(forPetWidth petWidth: CGFloat) -> CGFloat {
		subtitleContentWidth(forBubbleWidth: bubbleWidth(forPetWidth: petWidth))
	}
}

/// Formats the standby attention subtitle (`Re: …`) to fit the bubble width.
enum AttentionSubtitleFormatting {
	static let replyPrefix = "Re: "

	/// Truncate `excerpt` so `Re: ` + text (+ `...` when clipped) fits `maxWidth`.
	static func truncatedReplyLine(
		excerpt: String,
		fittingWidth maxWidth: CGFloat,
		font: NSFont = NSFont.systemFont(ofSize: 10)
	) -> String {
		let body = excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !body.isEmpty else { return "" }

		let full = replyPrefix + body
		if textWidth(full, font: font) <= maxWidth {
			return full
		}

		var trimmed = body
		while !trimmed.isEmpty {
			let candidate = replyPrefix + trimmed + "..."
			if textWidth(candidate, font: font) <= maxWidth {
				return candidate
			}
			trimmed.removeLast()
		}
		return replyPrefix + "..."
	}

	private static func textWidth(_ string: String, font: NSFont) -> CGFloat {
		(string as NSString).size(withAttributes: [.font: font]).width
	}
}
