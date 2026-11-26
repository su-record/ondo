import SwiftUI

/// A segmented control in the Astryx shape: a filled track with the selected segment raised.
struct SegmentedControl<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, title in
                Button { selection = value } label: {
                    Text(title)
                        .font(.system(size: 12, weight: selection == value ? .semibold : .regular))
                        .foregroundStyle(selection == value ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.element - 2)
                            .fill(selection == value ? DS.Palette.card : .clear)
                            .shadow(color: .black.opacity(selection == value ? 0.12 : 0), radius: 1, y: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .frame(height: DS.Height.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.element).fill(DS.Palette.fill))
    }
}

/// A small rounded choice; selected chips use the accent.
struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? DS.Palette.accent : Color.primary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(selected ? DS.Palette.accentMuted : DS.Palette.fill))
        }
        .buttonStyle(.plain)
    }
}

/// A bordered number field with its unit inside, kept within `range`.
struct FieldBox: View {
    let value: Int
    let range: ClosedRange<Int>
    let unit: String
    let set: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            TextField("", value: Binding(get: { value }, set: { set(min(max($0, range.lowerBound), range.upperBound)) }), format: .number)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 34)
            Text(unit).font(DS.Font.supporting).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: DS.Height.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.element).strokeBorder(DS.Palette.fieldBorder))
    }
}

/// A temperature bar from 0 to `scale`, with a tick at the limit.
struct HeatGauge: View {
    let celsius: Double?
    let limit: Double
    let scale: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(DS.Palette.fill)
                Capsule().fill(Color(nsColor: Heat(celsius: celsius, limit: limit).color))
                    .frame(width: width * min(max((celsius ?? 0) / scale, 0), 1))
                RoundedRectangle(cornerRadius: 1).fill(Color.primary)
                    .frame(width: 2, height: 14)
                    .offset(x: width * limit / scale - 1)
            }
        }
        .frame(height: 6)
    }
}

/// A menu-style row: full width, 32 pt high, highlighted on hover.
struct ListRow<Trailing: View>: View {
    let title: String
    let action: (() -> Void)?
    @ViewBuilder let trailing: () -> Trailing
    @State private var hovering = false

    init(_ title: String, action: (() -> Void)? = nil, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.action = action
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title).font(DS.Font.body).lineLimit(1)
            Spacer()
            trailing()
        }
        .padding(.horizontal, DS.Space.sm)
        .frame(height: DS.Height.md)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: DS.Radius.inner).fill(hovering && action != nil ? DS.Palette.fill : .clear))
        .onHover { hovering = $0 }
        .onTapGesture { action?() }
    }
}

/// A white card of rows, as in grouped settings.
struct FormCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text(title).font(DS.Font.label).foregroundStyle(.secondary).padding(.leading, DS.Space.xs)
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: DS.Radius.container).fill(DS.Palette.card))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.container).strokeBorder(DS.Palette.border))
        }
    }
}

/// One settings row: title and optional detail on the left, a control on the right.
struct FormRow<Control: View>: View {
    let title: String
    var detail: String?
    var divider = true
    @ViewBuilder let control: () -> Control

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(DS.Font.body)
                    if let detail { Text(detail).font(DS.Font.supporting).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 0)
                control()
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, 6)
            .frame(minHeight: DS.Height.row)
            if divider { Rectangle().fill(DS.Palette.border).frame(height: 1) }
        }
    }
}
