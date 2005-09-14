$value1 = ""
$value2 = true
$value3 = false

$mode1 = $value1 ? {
    "" => 755,
    default => 644
}

$mode2 = $value2 ? {
    true => 755,
    default => 644
}

$mode3 = $value3 ? {
    false => 755,
    default => 644
}

file { "/tmp/selectorvalues1": create => true, mode => $mode1 }
file { "/tmp/selectorvalues2": create => true, mode => $mode2 }
file { "/tmp/selectorvalues3": create => true, mode => $mode3 }