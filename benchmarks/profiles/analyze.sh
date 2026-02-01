#!/bin/bash
# Count samples by category from time profiler XML

echo "======================================================================"
echo "                   PROFILE SAMPLE ANALYSIS"
echo "======================================================================"
echo ""

total=$(grep -c '<row>' time_profile.xml)
echo "Total samples: $total"
echo ""

# Count tcmalloc samples
tcmalloc=$(grep 'name="tcmalloc' time_profile.xml | wc -l | tr -d ' ')
echo "Memory Allocation (tcmalloc):    $tcmalloc ($(echo "scale=1; $tcmalloc * 100 / $total" | bc)%)"

# Count HAMT operations
hamt_set=$(grep 'hamt::HAMT::set' time_profile.xml | wc -l | tr -d ' ')
hamt_cleanup=$(grep 'hamt::HAMT::_cleanup' time_profile.xml | wc -l | tr -d ' ')
hamt_ops=$((hamt_set + hamt_cleanup))
echo "HAMT Core Operations:             $hamt_ops ($(echo "scale=1; $hamt_ops * 100 / $total" | bc)%)"

# Count List operations
list_ops=$(grep 'std::collections::list::List' time_profile.xml | wc -l | tr -d ' ')
echo "List Operations:                  $list_ops ($(echo "scale=1; $list_ops * 100 / $total" | bc)%)"

# Count dyld (dynamic linker) 
dyld=$(grep 'name="dyld' time_profile.xml | wc -l | tr -d ' ')
echo "Dynamic Linker (dyld):            $dyld ($(echo "scale=1; $dyld * 100 / $total" | bc)%)"

# Count runtime init
objc=$(grep -E 'objc|SkyLight|libdispatch|libSystem' time_profile.xml | wc -l | tr -d ' ')
echo "Runtime Init (objc/frameworks):   $objc ($(echo "scale=1; $objc * 100 / $total" | bc)%)"

# Count sentinels (idle)
sentinel=$(grep '<sentinel/>' time_profile.xml | wc -l | tr -d ' ')
echo "Idle/Sentinel:                    $sentinel ($(echo "scale=1; $sentinel * 100 / $total" | bc)%)"

echo ""
echo "======================================================================"
