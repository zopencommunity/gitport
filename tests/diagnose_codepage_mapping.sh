#!/usr/bin/env bash
# ==============================================================================
# Diagnose Actual Codepage Mapping
# Tests what 0xb0 actually maps to on this specific system
# ==============================================================================

echo "========================================================================"
echo "          CODEPAGE MAPPING DIAGNOSTIC                                  "
echo "========================================================================"
echo ""

# ==============================================================================
# Test 1: What is the actual IBM-1047 mapping on this system?
# ==============================================================================
echo "[Test 1] What does 0xb0 map to in IBM-1047 on THIS system?"
echo ""

# Create file with 0xb0 byte
printf '\xb0' > /tmp/byte_b0.bin

# Convert from IBM-1047 to UTF-8
echo "Converting 0xb0 from IBM-1047 to UTF-8:"
iconv -f IBM-1047 -t UTF-8 /tmp/byte_b0.bin 2>&1 | xxd -g1
RESULT=$(iconv -f IBM-1047 -t UTF-8 /tmp/byte_b0.bin 2>&1 | xxd -p | tr -d '\n')

echo "Result: 0x$RESULT"
echo ""

case "$RESULT" in
    "c2ac")
        echo "  → This system: IBM-1047 0xb0 = U+00AC (¬ NOT SIGN)"
        echo "  → This is CORRECT per IBM-1047 spec"
        ;;
    "c2b0")
        echo "  → This system: IBM-1047 0xb0 = U+00B0 (° DEGREE SIGN)"
        echo "  → This is DIFFERENT from standard IBM-1047!"
        echo "  → May be using IBM-037 or variant"
        ;;
    "5e")
        echo "  → This system: IBM-1047 0xb0 = ^ (CIRCUMFLEX)"
        echo "  → Unexpected mapping!"
        ;;
    *)
        echo "  → Unknown mapping: 0x$RESULT"
        ;;
esac

# ==============================================================================
# Test 2: What about 0x5f?
# ==============================================================================
echo ""
echo "[Test 2] What does 0x5f map to in IBM-1047 on THIS system?"
echo ""

printf '\x5f' > /tmp/byte_5f.bin
echo "Converting 0x5f from IBM-1047 to UTF-8:"
iconv -f IBM-1047 -t UTF-8 /tmp/byte_5f.bin 2>&1 | xxd -g1
RESULT_5F=$(iconv -f IBM-1047 -t UTF-8 /tmp/byte_5f.bin 2>&1 | xxd -p | tr -d '\n')

echo "Result: 0x$RESULT_5F"
echo ""

case "$RESULT_5F" in
    "c2ac")
        echo "  → This system: IBM-1047 0x5f = U+00AC (¬ NOT SIGN)"
        ;;
    "5e")
        echo "  → This system: IBM-1047 0x5f = ^ (CIRCUMFLEX)"
        echo "  → This is CORRECT per IBM-1047 spec"
        ;;
    *)
        echo "  → Mapping: 0x$RESULT_5F"
        ;;
esac

# ==============================================================================
# Test 3: Reverse - UTF-8 NOT SIGN to IBM-1047
# ==============================================================================
echo ""
echo "[Test 3] How does U+00AC (¬ NOT SIGN) convert to IBM-1047?"
echo ""

# U+00AC in UTF-8 is 0xc2 0xac
printf '\xc2\xac' > /tmp/utf8_not.bin
echo "Converting U+00AC (¬) from UTF-8 to IBM-1047:"
iconv -f UTF-8 -t IBM-1047 /tmp/utf8_not.bin 2>&1 | xxd -g1
RESULT_NOT=$(iconv -f UTF-8 -t IBM-1047 /tmp/utf8_not.bin 2>&1 | xxd -p | tr -d '\n')

echo "Result: 0x$RESULT_NOT"
echo ""

case "$RESULT_NOT" in
    "b0")
        echo "  → U+00AC (¬) → IBM-1047 0xb0"
        echo "  → On this system, NOT SIGN maps to 0xb0"
        ;;
    "5f")
        echo "  → U+00AC (¬) → IBM-1047 0x5f"
        echo "  → On this system, NOT SIGN maps to 0x5f (standard)"
        ;;
    *)
        echo "  → Converted to: 0x$RESULT_NOT"
        ;;
esac

# ==============================================================================
# Test 4: Test IBM-037 mappings
# ==============================================================================
echo ""
echo "[Test 4] Compare with IBM-037 mappings"
echo ""

echo "IBM-037 0xb0 to UTF-8:"
printf '\xb0' | iconv -f IBM-037 -t UTF-8 2>&1 | xxd -g1
RESULT_037=$(printf '\xb0' | iconv -f IBM-037 -t UTF-8 2>&1 | xxd -p | tr -d '\n')
echo "Result: 0x$RESULT_037"

case "$RESULT_037" in
    "c2ac")
        echo "  → IBM-037 0xb0 = U+00AC (¬ NOT SIGN)"
        ;;
    "5e")
        echo "  → IBM-037 0xb0 = ^ (CIRCUMFLEX)"
        ;;
    *)
        echo "  → IBM-037 0xb0 = 0x$RESULT_037"
        ;;
esac

# ==============================================================================
# Test 5: Character table
# ==============================================================================
echo ""
echo "[Test 5] Key character mappings on THIS system"
echo ""
echo "Byte | IBM-1047→UTF-8 | IBM-037→UTF-8 | Character"
echo "-----|----------------|---------------|----------"

for byte in 5e 5f b0; do
    # IBM-1047
    MAP_1047=$(printf "\\x$byte" | iconv -f IBM-1047 -t UTF-8 2>/dev/null | xxd -p | tr -d '\n')
    CHAR_1047=$(printf "\\x$byte" | iconv -f IBM-1047 -t UTF-8 2>/dev/null || echo "?")
    
    # IBM-037
    MAP_037=$(printf "\\x$byte" | iconv -f IBM-037 -t UTF-8 2>/dev/null | xxd -p | tr -d '\n')
    CHAR_037=$(printf "\\x$byte" | iconv -f IBM-037 -t UTF-8 2>/dev/null || echo "?")
    
    printf "0x%-2s | %-14s | %-13s | 1047:%s 037:%s\n" \
           "$byte" "$MAP_1047" "$MAP_037" "$CHAR_1047" "$CHAR_037"
done

# ==============================================================================
# Test 6: Test the user's specific scenario
# ==============================================================================
echo ""
echo "[Test 6] Simulate user's file conversion"
echo ""

# Create a UTF-8 file with NOT symbol like user had
cat > /tmp/user_file.txt << 'EOF'
IF (I) THEN ! Same as If I¬=0
