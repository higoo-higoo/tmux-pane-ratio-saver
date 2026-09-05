# Parse, validate, inspect, and serialize tmux's classic window layout format.
#
# Usage:
#   awk -v mode=validate  -f scale-layout.awk  # one layout on stdin
#   awk -v mode=signature -f scale-layout.awk  # one layout on stdin
#   awk -v mode=shape     -f scale-layout.awk  # one layout on stdin
#   awk -v mode=serialize -f scale-layout.awk  # one layout on stdin
#   awk -v mode=scale     -f scale-layout.awk  # reference and current layouts
#   awk -v mode=rebind    -f scale-layout.awk  # preserve geometry, copy pane order

BEGIN {
    comma = ","
    next_node = 0
}

{
    input[NR] = $0
}

END {
    if (mode == "")
        mode = "validate"

    if (mode == "validate" || mode == "signature" || mode == "shape" || mode == "serialize") {
        if (NR != 1) {
            report("expected exactly one layout")
            exit 2
        }

        root = parse_layout(input[1], 1)
        if (!root) {
            report(parse_error)
            exit 2
        }

        if (mode == "signature")
            print topology(root)
        else if (mode == "shape")
            print structure(root)
        else if (mode == "serialize") {
            body = serialize(root)
            print checksum(body) "," body
        }
        exit 0
    }

    if (mode == "rebind") {
        if (NR != 2) {
            report("expected reference and current layouts")
            exit 2
        }

        reference_root = parse_layout(input[1], 1)
        if (!reference_root) {
            report("invalid reference: " parse_error)
            exit 2
        }
        current_root = parse_layout(input[2], 2)
        if (!current_root) {
            report("invalid current layout: " parse_error)
            exit 2
        }
        if (structure(reference_root) != structure(current_root) ||
            !same_pane_set(reference_root, current_root)) {
            report("layout structure or pane set differs")
            exit 3
        }

        copy_pane_order(reference_root, current_root)
        body = serialize(reference_root)
        print checksum(body) comma body
        exit 0
    }

    if (mode == "scale") {
        if (NR != 2) {
            report("expected reference and current layouts")
            exit 2
        }

        reference_root = parse_layout(input[1], 1)
        if (!reference_root) {
            report("invalid reference: " parse_error)
            exit 2
        }
        current_root = parse_layout(input[2], 2)
        if (!current_root) {
            report("invalid current layout: " parse_error)
            exit 2
        }
        if (topology(reference_root) != topology(current_root)) {
            report("layout topology differs")
            exit 3
        }

        calculate_minimum(reference_root)
        scaled_width = (target_width == "" ? node_width[current_root] : target_width + 0)
        scaled_height = (target_height == "" ? node_height[current_root] : target_height + 0)
        if (scaled_width < 1 || scaled_height < 1 ||
            !scale_node(reference_root, scaled_width, scaled_height,
                        node_x[current_root], node_y[current_root])) {
            report("target is smaller than the layout minimum")
            exit 4
        }

        body = serialize(reference_root)
        print checksum(body) comma body
        exit 0
    }

    report("unknown mode: " mode)
    exit 2
}

function report(message) {
    if (debug)
        print "scale-layout.awk: " message > "/dev/stderr"
}

function fail(message) {
    if (parse_error == "")
        parse_error = message " at byte " cursor
    return 0
}

function is_hex(value,    i, c) {
    if (length(value) != 4)
        return 0
    for (i = 1; i <= 4; i++) {
        c = substr(value, i, 1)
        if (index("0123456789abcdefABCDEF", c) == 0)
            return 0
    }
    return 1
}

function parse_layout(layout, tree_id,    separator, supplied, body, root) {
    parse_error = ""
    separator = index(layout, comma)
    if (!separator)
        return fail("missing checksum separator")

    supplied = substr(layout, 1, separator - 1)
    body = substr(layout, separator + 1)
    if (!is_hex(supplied))
        return fail("invalid checksum field")
    if (body == "")
        return fail("empty layout body")
    if (tolower(supplied) != checksum(body))
        return fail("checksum mismatch")

    source = body
    source_length = length(source)
    cursor = 1
    current_tree = tree_id
    root = parse_cell()
    if (!root)
        return 0
    if (cursor <= source_length)
        return fail("trailing input")
    if (!validate_node(root, tree_id))
        return 0
    return root
}

function parse_uint(require_positive, field_name,    start, c, text, value) {
    start = cursor
    while (cursor <= source_length) {
        c = substr(source, cursor, 1)
        if (c < "0" || c > "9")
            break
        cursor++
    }
    if (cursor == start) {
        fail("missing " field_name)
        return -1
    }
    text = substr(source, start, cursor - start)
    value = text + 0
    if (require_positive && value < 1) {
        fail(field_name " must be positive")
        return -1
    }
    return value
}

function expect(character, description) {
    if (substr(source, cursor, 1) != character)
        return fail("expected " description)
    cursor++
    return 1
}

function parse_cell(    node, width, height, x, y, token, closing, kind, count, child, pane) {
    width = parse_uint(1, "width")
    if (width < 0 || !expect("x", "x after width"))
        return 0
    height = parse_uint(1, "height")
    if (height < 0 || !expect(comma, "comma after height"))
        return 0
    x = parse_uint(0, "x offset")
    if (x < 0 || !expect(comma, "comma after x offset"))
        return 0
    y = parse_uint(0, "y offset")
    if (y < 0)
        return 0

    node = ++next_node
    node_width[node] = width
    node_height[node] = height
    node_x[node] = x
    node_y[node] = y
    node_tree[node] = current_tree

    token = substr(source, cursor, 1)
    if (token == comma) {
        cursor++
        pane = parse_uint(0, "pane id")
        if (pane < 0)
            return 0
        node_kind[node] = "leaf"
        node_pane[node] = pane
        return node
    }

    if (token != "{" && token != "[")
        return fail("expected pane id or child container")

    if (token == "{") {
        kind = "left_right"
        closing = "}"
    } else {
        kind = "top_bottom"
        closing = "]"
    }
    node_kind[node] = kind
    cursor++

    count = 0
    while (1) {
        child = parse_cell()
        if (!child)
            return 0
        node_child[node, ++count] = child

        token = substr(source, cursor, 1)
        if (token == closing) {
            cursor++
            break
        }
        if (token != comma)
            return fail("expected child separator or closing delimiter")
        cursor++
    }
    node_count[node] = count
    if (count < 2)
        return fail("container must have at least two children")
    return node
}

function validate_node(node, tree_id,    kind, count, i, child, previous, total, pane) {
    kind = node_kind[node]
    if (kind == "leaf") {
        pane = node_pane[node]
        if ((tree_id, pane) in seen_pane)
            return fail("duplicate pane id " pane)
        seen_pane[tree_id, pane] = 1
        return 1
    }

    count = node_count[node]
    if (count < 2)
        return fail("container must have at least two children")

    total = count - 1
    for (i = 1; i <= count; i++) {
        child = node_child[node, i]
        if (!validate_node(child, tree_id))
            return 0

        if (kind == "left_right") {
            if (node_height[child] != node_height[node] || node_y[child] != node_y[node])
                return fail("left-right child height or y offset is inconsistent")
            if (i == 1) {
                if (node_x[child] != node_x[node])
                    return fail("left-right first child offset is inconsistent")
            } else if (node_x[child] != node_x[previous] + node_width[previous] + 1)
                return fail("left-right child offsets are not continuous")
            total += node_width[child]
        } else if (kind == "top_bottom") {
            if (node_width[child] != node_width[node] || node_x[child] != node_x[node])
                return fail("top-bottom child width or x offset is inconsistent")
            if (i == 1) {
                if (node_y[child] != node_y[node])
                    return fail("top-bottom first child offset is inconsistent")
            } else if (node_y[child] != node_y[previous] + node_height[previous] + 1)
                return fail("top-bottom child offsets are not continuous")
            total += node_height[child]
        } else
            return fail("unsupported node kind")
        previous = child
    }

    if (kind == "left_right" && total != node_width[node])
        return fail("left-right child widths do not fill parent")
    if (kind == "top_bottom" && total != node_height[node])
        return fail("top-bottom child heights do not fill parent")
    return 1
}

function topology(node,    result, i) {
    if (node_kind[node] == "leaf")
        return "LEAF:" node_pane[node]

    result = (node_kind[node] == "left_right" ? "LR(" : "TB(")
    for (i = 1; i <= node_count[node]; i++) {
        if (i > 1)
            result = result comma
        result = result topology(node_child[node, i])
    }
    return result ")"
}

function structure(node,    result, i) {
    if (node_kind[node] == "leaf")
        return "LEAF"

    result = (node_kind[node] == "left_right" ? "LR(" : "TB(")
    for (i = 1; i <= node_count[node]; i++) {
        if (i > 1)
            result = result comma
        result = result structure(node_child[node, i])
    }
    return result ")"
}

function same_pane_set(reference, current,    pane, i) {
    if (node_kind[reference] == "leaf") {
        pane = node_pane[reference]
        return ((2, pane) in seen_pane)
    }
    for (i = 1; i <= node_count[reference]; i++) {
        if (!same_pane_set(node_child[reference, i], current))
            return 0
    }
    return 1
}

function copy_pane_order(reference, current,    i) {
    if (node_kind[reference] == "leaf") {
        node_pane[reference] = node_pane[current]
        return
    }
    for (i = 1; i <= node_count[reference]; i++)
        copy_pane_order(node_child[reference, i], node_child[current, i])
}

function serialize(node,    result, i) {
    result = node_width[node] "x" node_height[node] comma node_x[node] comma node_y[node]
    if (node_kind[node] == "leaf")
        return result comma node_pane[node]

    result = result (node_kind[node] == "left_right" ? "{" : "[")
    for (i = 1; i <= node_count[node]; i++) {
        if (i > 1)
            result = result comma
        result = result serialize(node_child[node, i])
    }
    return result (node_kind[node] == "left_right" ? "}" : "]")
}

function maximum(left, right) {
    return left > right ? left : right
}

function calculate_minimum(node,    kind, count, i, child, width, height) {
    kind = node_kind[node]
    if (kind == "leaf") {
        node_min_width[node] = 1
        node_min_height[node] = 1
        return
    }

    count = node_count[node]
    if (kind == "left_right") {
        width = count - 1
        height = 1
        for (i = 1; i <= count; i++) {
            child = node_child[node, i]
            calculate_minimum(child)
            width += node_min_width[child]
            height = maximum(height, node_min_height[child])
        }
    } else {
        width = 1
        height = count - 1
        for (i = 1; i <= count; i++) {
            child = node_child[node, i]
            calculate_minimum(child)
            width = maximum(width, node_min_width[child])
            height += node_min_height[child]
        }
    }
    node_min_width[node] = width
    node_min_height[node] = height
}

# Allocate total cells across a container's children. A largest-remainder pass
# is repeated after children that need their structural minimum are fixed.
function allocate_children(node, total, axis,    count, i, child, minimum, required, active_count, remaining, weight_sum, ideal, floor_sum, extras, best, best_fraction, fixed_any) {
    count = node_count[node]
    required = 0
    active_count = count
    remaining = total

    for (i = 1; i <= count; i++) {
        child = node_child[node, i]
        minimum = (axis == "width" ? node_min_width[child] : node_min_height[child])
        allocation_min[node, i] = minimum
        allocation_active[node, i] = 1
        allocation_value[node, i] = 0
        required += minimum
    }
    if (total < required)
        return 0

    while (active_count > 0) {
        weight_sum = 0
        for (i = 1; i <= count; i++) {
            if (!allocation_active[node, i])
                continue
            child = node_child[node, i]
            weight_sum += (axis == "width" ? node_width[child] : node_height[child])
        }

        floor_sum = 0
        for (i = 1; i <= count; i++) {
            if (!allocation_active[node, i])
                continue
            child = node_child[node, i]
            ideal = remaining * (axis == "width" ? node_width[child] : node_height[child]) / weight_sum
            allocation_floor[node, i] = int(ideal)
            allocation_fraction[node, i] = ideal - int(ideal)
            allocation_bonus[node, i] = 0
            floor_sum += int(ideal)
        }

        extras = remaining - floor_sum
        while (extras > 0) {
            best = 0
            best_fraction = -1
            for (i = 1; i <= count; i++) {
                if (!allocation_active[node, i] || allocation_bonus[node, i])
                    continue
                if (allocation_fraction[node, i] > best_fraction + 0.000000000001) {
                    best = i
                    best_fraction = allocation_fraction[node, i]
                }
            }
            if (!best)
                return 0
            allocation_bonus[node, best] = 1
            extras--
        }

        fixed_any = 0
        for (i = 1; i <= count; i++) {
            if (!allocation_active[node, i])
                continue
            allocation_candidate[node, i] = allocation_floor[node, i] + allocation_bonus[node, i]
            if (allocation_candidate[node, i] < allocation_min[node, i]) {
                allocation_value[node, i] = allocation_min[node, i]
                remaining -= allocation_min[node, i]
                allocation_active[node, i] = 0
                active_count--
                fixed_any = 1
            }
        }

        if (!fixed_any) {
            for (i = 1; i <= count; i++) {
                if (allocation_active[node, i])
                    allocation_value[node, i] = allocation_candidate[node, i]
            }
            return 1
        }
        if (active_count == 0)
            return remaining == 0
    }
    return remaining == 0
}

function scale_node(node, width, height, x, y,    kind, count, available, i, child, child_width, child_height, child_x, child_y) {
    if (width < node_min_width[node] || height < node_min_height[node])
        return 0

    node_width[node] = width
    node_height[node] = height
    node_x[node] = x
    node_y[node] = y
    kind = node_kind[node]
    if (kind == "leaf")
        return 1

    count = node_count[node]
    if (kind == "left_right") {
        available = width - (count - 1)
        if (!allocate_children(node, available, "width"))
            return 0
        child_x = x
        for (i = 1; i <= count; i++) {
            child = node_child[node, i]
            child_width = allocation_value[node, i]
            if (!scale_node(child, child_width, height, child_x, y))
                return 0
            child_x += child_width + 1
        }
    } else {
        available = height - (count - 1)
        if (!allocate_children(node, available, "height"))
            return 0
        child_y = y
        for (i = 1; i <= count; i++) {
            child = node_child[node, i]
            child_height = allocation_value[node, i]
            if (!scale_node(child, width, child_height, x, child_y))
                return 0
            child_y += child_height + 1
        }
    }
    return 1
}

function byte_value(character) {
    if (character >= "0" && character <= "9")
        return 48 + character
    if (character == comma)
        return 44
    if (character == "x")
        return 120
    if (character == "{")
        return 123
    if (character == "}")
        return 125
    if (character == "[")
        return 91
    if (character == "]")
        return 93
    return -1
}

function checksum(body,    sum, i, byte, low_bit) {
    sum = 0
    for (i = 1; i <= length(body); i++) {
        byte = byte_value(substr(body, i, 1))
        if (byte < 0)
            return "unsupported"
        low_bit = sum % 2
        sum = int(sum / 2) + low_bit * 32768
        sum = (sum + byte) % 65536
    }
    return sprintf("%04x", sum)
}
