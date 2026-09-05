# Parse, validate, inspect, and serialize tmux's classic window layout format.
#
# Usage:
#   awk -v mode=validate  -f scale-layout.awk  # one layout on stdin
#   awk -v mode=signature -f scale-layout.awk  # one layout on stdin
#   awk -v mode=serialize -f scale-layout.awk  # one layout on stdin
#
# The scaler mode is added below with the same parser as its foundation.

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

    if (mode == "validate" || mode == "signature" || mode == "serialize") {
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
        else if (mode == "serialize") {
            body = serialize(root)
            print checksum(body) "," body
        }
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
