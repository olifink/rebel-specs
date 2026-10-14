\ 07-FLOATING-POINT.fth -- reference source for the float wordset's
\ Forth-source layer (07-FLOATING-POINT.md section 5.1 and 5.2).
\ Normative: a target's results must be bit-identical to these.
\ Needs the eight KERNEL float words (section 4) and the core words.
\ Every constant is the exact binary32 bit pattern, in hex. A pattern
\ with bit 31 set is read as a negative cell, which is the same bits.

HEX
3F800000 CONSTANT F1          \ 1.0
3F000000 CONSTANT F0.5        \ 0.5
42000000 CONSTANT F32         \ 32.0
4B800000 CONSTANT TWO24       \ 16777216.0 = 2^24
7FC00000 CONSTANT FNAN        \ the one NaN (section 3, rule 6)
7F800000 CONSTANT F+INF
FF800000 CONSTANT F-INF
80000000 CONSTANT SIGN-BIT
3FB8AA3B CONSTANT INVLN2      \ 1/ln 2
3F317200 CONSTANT LN2HI       \ ln 2, high part (16 bits)
35BFBE8E CONSTANT LN2LO       \ ln 2 - LN2HI
42B17218 CONSTANT EXP-MAX     \ above this e^x overflows
C2CFF1B4 CONSTANT EXP-MIN     \ below this e^x underflows to 0
3FB504F3 CONSTANT SQRT2
3F22F983 CONSTANT TWO/PI
3FC90000 CONSTANT PI/2HI      \ pi/2, high part (9 bits)
39FDAA22 CONSTANT PI/2LO      \ pi/2 - PI/2HI
3F490FDB CONSTANT PI/4
3FC90FDB CONSTANT PI/2
3ED413CD CONSTANT TAN-PI/8
DECIMAL

\ ---- 5.1 derived arithmetic and tests ----

: FNAN?    ( r -- flag )  DUP F= 0= ;
: FINITE?  ( r -- flag )  SIGN-BIT INVERT AND  F+INF < ;
: FNEGATE  ( r -- -r )    DUP FNAN? IF DROP FNAN EXIT THEN  SIGN-BIT XOR ;
: FABS     ( r -- |r| )   DUP FNAN? IF DROP FNAN EXIT THEN  SIGN-BIT INVERT AND ;
: F-       ( r1 r2 -- r3 ) FNEGATE F+ ;
: F0=      ( r -- flag )  FABS 0= ;
: F0<      ( r -- flag )  0 F< ;
: F>       ( r1 r2 -- flag ) SWAP F< ;
: FMIN     ( r1 r2 -- r3 )
  OVER FNAN? OVER FNAN? OR IF 2DROP FNAN EXIT THEN
  2DUP F< IF DROP ELSE NIP THEN ;
: FMAX     ( r1 r2 -- r3 )
  OVER FNAN? OVER FNAN? OR IF 2DROP FNAN EXIT THEN
  2DUP F< IF NIP ELSE DROP THEN ;
: FTRUNC   ( r -- r' )    \ toward zero; |r| >= 2^24, infinities unchanged
  DUP FNAN? IF DROP FNAN EXIT THEN
  DUP FABS TWO24 F< IF F>S S>F THEN ;
: FLOOR    ( r -- r' )    DUP FTRUNC TUCK F< IF F1 F- THEN ;

\ ---- helpers ----

\ Horner's rule: n coefficients at addr, highest power first.
VARIABLE PZ
: POLY  ( z addr n -- r )
  ROT PZ !  OVER @ -ROT
  1 DO  CELL+ SWAP PZ @ F* OVER @ F+ SWAP  LOOP  DROP ;

\ 2^n as a float, for -126 <= n <= 127.
: 2^N   ( n -- r )  127 + 8388608 * ;

\ ---- 5.2 elementary functions ----

\ e^x: x = k ln2 + r with |r| <= ln2/2, e^r by Taylor series to r^7,
\ then scaled by 2^k in two halves so each factor is a normal number.
CREATE EXP-C  HEX
  39500D01 , 3AB60B61 , 3C088889 , 3D2AAAAB ,   \ 1/7! 1/6! 1/5! 1/4!
  3E2AAAAB , 3F000000 , 3F800000 , 3F800000 ,   \ 1/3! 1/2! 1 1
DECIMAL
: FEXP  ( r -- e^r )
  DUP FNAN? IF DROP FNAN EXIT THEN
  DUP EXP-MAX F> IF DROP F+INF EXIT THEN
  DUP EXP-MIN F< IF DROP 0 EXIT THEN
  DUP INVLN2 F*  OVER F0< IF F0.5 F- ELSE F0.5 F+ THEN  F>S   ( x k )
  DUP >R S>F  TUCK LN2HI F* F-  SWAP LN2LO F* F-              ( r )
  EXP-C 8 POLY
  R> DUP 2/ TUCK -  >R 2^N F*  R> 2^N F* ;

\ ln x: x = 2^k m with sqrt(1/2) < m <= sqrt(2); ln m = 2 atanh s,
\ s = (m-1)/(m+1), by its series to s^9; plus k ln2.
CREATE LN-C  HEX
  3DE38E39 , 3E124925 , 3E4CCCCD , 3EAAAAAB , 3F800000 ,  \ 1/9 1/7 1/5 1/3 1
DECIMAL
: FLN  ( r -- ln r )
  DUP FNAN? IF DROP FNAN EXIT THEN
  DUP F0< IF DROP FNAN EXIT THEN
  DUP F0= IF DROP F-INF EXIT THEN
  DUP F+INF = IF EXIT THEN
  0 >R
  DUP 8388608 < IF  TWO24 F*  R> 24 - >R  THEN      \ subnormal
  DUP 8388608 / 127 -  R> + >R                       \ exponent
  8388607 AND F1 OR                                  \ m in [1,2)
  DUP SQRT2 F> IF  F0.5 F*  R> 1+ >R  THEN
  DUP F1 F- SWAP F1 F+ F/                            ( s )
  DUP DUP F* LN-C 5 POLY  SWAP DUP F+ F*             ( ln m )
  R> S>F  DUP LN2LO F* ROT F+  SWAP LN2HI F* F+ ;

\ sin and cos: |x| = n pi/2 + y with |y| <= pi/4, then a Taylor
\ series for sin y (to y^9) or cos y (to y^10) chosen by n mod 4.
CREATE SIN-C  HEX
  3638EF1D , B9500D01 , 3C088889 , BE2AAAAB , 3F800000 ,  \ 1/9! -1/7! 1/5! -1/3! 1
DECIMAL
CREATE COS-C  HEX
  B493F27E , 37D00D01 , BAB60B61 , 3D2AAAAB , BF000000 , 3F800000 ,
DECIMAL                       \ -1/10! 1/8! -1/6! 1/4! -1/2 1
: KSIN  ( y -- sin y )  DUP DUP F* SIN-C 5 POLY F* ;
: KCOS  ( y -- cos y )  DUP F* COS-C 6 POLY ;
: FREDUCE  ( a -- y q )       \ a >= 0, finite
  DUP TWO/PI F* F0.5 F+ F>S  DUP >R  S>F
  TUCK PI/2HI F* F-  SWAP PI/2LO F* F-  R> 3 AND ;
: FSIN  ( r -- sin r )
  DUP FINITE? 0= IF DROP FNAN EXIT THEN
  DUP F0< >R  FABS FREDUCE
  DUP 1 AND IF SWAP KCOS ELSE SWAP KSIN THEN
  SWAP 2 AND IF FNEGATE THEN
  R> IF FNEGATE THEN ;
: FCOS  ( r -- cos r )
  DUP FINITE? 0= IF DROP FNAN EXIT THEN
  FABS FREDUCE
  DUP 1 AND IF SWAP KSIN ELSE SWAP KCOS THEN
  SWAP 1+ 2 AND IF FNEGATE THEN ;
: FTAN  ( r -- tan r )  DUP FSIN SWAP FCOS F/ ;

\ atan x: |x| > 1 uses pi/2 - atan(1/|x|); then |x| > tan(pi/8) uses
\ pi/4 + atan((x-1)/(x+1)); the rest by the Taylor series to x^15.
CREATE ATAN-C  HEX
  BD888889 , 3D9D89D9 , BDBA2E8C , 3DE38E39 ,   \ -1/15 1/13 -1/11 1/9
  BE124925 , 3E4CCCCD , BEAAAAAB , 3F800000 ,   \ -1/7 1/5 -1/3 1
DECIMAL
VARIABLE AINV  VARIABLE AOFF
: FATAN  ( r -- atan r )
  DUP FNAN? IF DROP FNAN EXIT THEN
  DUP F0< >R  FABS
  DUP F1 F> DUP AINV !  IF F1 SWAP F/ THEN
  0 AOFF !
  DUP TAN-PI/8 F> IF  DUP F1 F- SWAP F1 F+ F/  PI/4 AOFF !  THEN
  DUP DUP F* ATAN-C 8 POLY F*  AOFF @ F+
  AINV @ IF PI/2 SWAP F- THEN
  R> IF FNEGATE THEN ;

\ x^n for an integer n, by repeated squaring.
: F**N  ( r n -- r' )
  DUP 0< >R ABS  F1 -ROT
  BEGIN DUP WHILE
    DUP 1 AND IF  ROT 2 PICK F* -ROT  THEN
    SWAP DUP F* SWAP 2/
  REPEAT 2DROP
  R> IF F1 SWAP F/ THEN ;

\ x^y: y = 0 gives 1; an integral |y| <= 32 uses F**N; a negative x
\ needs an integral y, its sign from y's parity; otherwise e^(y ln x).
: FINTEGRAL?  ( r -- flag )  DUP FTRUNC F= ;
: F**  ( x y -- x^y )
  DUP F0= IF 2DROP F1 EXIT THEN
  DUP FINTEGRAL? IF  DUP FABS F32 F> 0= IF F>S F**N EXIT THEN  THEN
  OVER F0< IF
    DUP FINTEGRAL? 0= IF 2DROP FNAN EXIT THEN
    DUP FABS TWO24 F< IF DUP F>S 1 AND ELSE 0 THEN >R
    SWAP FABS FLN F* FEXP  R> IF FNEGATE THEN EXIT
  THEN
  SWAP FLN F* FEXP ;
