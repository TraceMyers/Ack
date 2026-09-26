#if FLIP_VECTOR_2D_Y_AXIS {
    VECTOR2_UP      :: Vector2.{ 0, -1};
    VECTOR2_DOWN    :: Vector2.{ 0,  1};
    Y_POSITIVE_DIRECTION_2D :: Direction_2D.DOWN;
    Y_NEGATIVE_DIRECTION_2D :: Direction_2D.UP;
} else {
    VECTOR2_UP      :: Vector2.{ 0,  1};
    VECTOR2_DOWN    :: Vector2.{ 0, -1};
    Y_POSITIVE_DIRECTION_2D :: Direction_2D.UP;
    Y_NEGATIVE_DIRECTION_2D :: Direction_2D.DOWN;
}
VECTOR2_RIGHT   :: Vector2.{ 1,  0};
VECTOR2_LEFT    :: Vector2.{-1,  0};
VECTOR3_FORE    :: Vector3.{ 0,  1,  0};
VECTOR3_BACK    :: Vector3.{ 0, -1,  0};
VECTOR3_RIGHT   :: Vector3.{ 1,  0,  0};
VECTOR3_LEFT    :: Vector3.{-1,  0,  0};
VECTOR3_UP      :: Vector3.{ 0,  0,  1};
VECTOR3_DOWN    :: Vector3.{ 0,  0, -1};

// some convenient values, 'small' relative to the precision of 1.0
SMALLISH_NUMBER     :: 0.003;
SMALL_NUMBER        :: 0.00001;
VERY_SMALL_NUMBER   :: 0.0000005;

INV_PI          :: 1.0 / PI;
INV_2_PI        :: 1.0 / (2.0 * PI);

COS_0            :: 1.0;
ALMOST_COS_0     :: COS_PI_OVER_2048;
COS_PI_OVER_2048 :: #run cos(PI/2048); // ~0.09 degrees
COS_PI_OVER_128  :: #run cos(PI/128);
COS_PI_OVER_64   :: #run cos(PI/64);
COS_PI_OVER_32   :: #run cos(PI/32);
COS_PI_OVER_28   :: #run cos(PI/28);
COS_PI_OVER_24   :: #run cos(PI/24);
COS_PI_OVER_20   :: #run cos(PI/20);
COS_PI_OVER_16   :: #run cos(PI/16);
COS_PI_OVER_12   :: #run cos(PI/12);
COS_PI_OVER_8    :: #run cos(PI/8);
COS_PI_OVER_7    :: #run cos(PI/7);
COS_PI_OVER_6    :: #run cos(PI/6);
COS_PI_OVER_5    :: #run cos(PI/5);
COS_PI_OVER_4    :: #run cos(PI/4);
COS_PI_OVER_3    :: #run cos(PI/2);
COS_PI_OVER_2    :: 0.0;

SIN_PI_OVER_16   :: #run sin(PI/16);
SIN_PI_OVER_12   :: #run sin(PI/12);
SIN_PI_OVER_8    :: #run sin(PI/8);
SIN_PI_OVER_7    :: #run sin(PI/7);
SIN_PI_OVER_6    :: #run sin(PI/6);
SIN_PI_OVER_5    :: #run sin(PI/5);
SIN_PI_OVER_4    :: #run sin(PI/4);
SIN_PI_OVER_3    :: #run sin(PI/2);
SIN_PI_OVER_2    :: 1.0;

FloatTypes :: Type.[float32, float64];
VectorTypes :: Type.[Vector2, Vector3, Vector4, Vector2d, Quaternion];  // Used for type restriction in normalize().
Vector2Types :: Type.[Vector2, Vector2i, Vector2d];
Vector3Types :: Type.[Vector3, Vector3i];
VectorAndFloatTypes :: Type.[Vector2, Vector3, Vector4, Vector2d, Quaternion, float32, float64];  // Used for type restriction in normalize().

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.
