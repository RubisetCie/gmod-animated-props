//glua-quaternion library by JWalkerMailly (https://github.com/JWalkerMailly/glua-quaternion)
//Included for a single piece of quaternion-related code in prop_animated, an emulation of valve code to calculate bone angular velocity for ragdollize-on-damage

--[[
MIT License

Copyright (c) 2023 WLKRE

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]


---
-- This module defines a quaternion data structure and associated operations for 3D rotations.
-- @module Quaternion
-- @author WLKRE
--
local QUATERNION = {
	__epsl = 0.0001,
	__lerp = 0.9995,
	__axis = Vector()
};

QUATERNION.__index = QUATERNION;
debug.getregistry().Quaternion = QUATERNION;

local setmetatable = setmetatable
local getmetatable = getmetatable
local math = math

---
-- Checks if an object is a quaternion.
-- @param  obj The object to check.
-- @return boolean 'true' if the object is a quaternion, 'false' otherwise.
--
local function IsQuaternion(obj)
	return getmetatable(obj) == QUATERNION;
end

---
-- Set the values of the quaternion.
-- @param  w The 'w' component of the quaternion or a Quaternion object to copy.
-- @param  x The 'x' component of the quaternion.
-- @param  y The 'y' component of the quaternion.
-- @param  z The 'z' component of the quaternion.
-- @return quaternion The modified quaternion.
--
function QUATERNION:Set(w, x, y, z)
	if (IsQuaternion(w)) then self.w, self.x, self.y, self.z = w.w, w.x, w.y, w.z;
						 else self.w, self.x, self.y, self.z = w, x, y, z; end
	return self;
end

---
-- Create a new quaternion.
-- If a single argument 'w' is provided, it assumes a quaternion object was passed in to copy the
-- values from. If 'w' and 'x', 'y', and 'z' are provided, it creates a quaternion with the provided values.
-- @param  w (Optional) The 'w' component of the quaternion or a Quaternion object to copy.
-- @param  x (Optional) The 'x' component of the quaternion.
-- @param  y (Optional) The 'y' component of the quaternion.
-- @param  z (Optional) The 'z' component of the quaternion.
-- @return quaternion A new quaternion.
--
function Quaternion(w --[[ 1.0 ]], x --[[ 0.0 ]], y --[[ 0.0 ]], z --[[ 0.0 ]])

	return IsQuaternion(w)
		&& setmetatable({ w = w.w, x = w.x, y = w.y, z = w.z }, QUATERNION)
		|| setmetatable({ w = w || 1.0, x = x || 0.0, y = y || 0.0, z = z || 0.0 }, QUATERNION);
end

---
-- Set the quaternion using Euler angles.
-- @param  ang An angle with 'p', 'y', and 'r' keys representing pitch, yaw, and roll angles.
-- @return quaternion The modified quaternion.
--
function QUATERNION:SetAngle(ang)

	local p    = math.rad(ang.p) * 0.5;
	local y    = math.rad(ang.y) * 0.5;
	local r    = math.rad(ang.r) * 0.5;
	local sinp = math.sin(p);
	local cosp = math.cos(p);
	local siny = math.sin(y);
	local cosy = math.cos(y);
	local sinr = math.sin(r);
	local cosr = math.cos(r);

	return self:Set(
		cosr * cosp * cosy + sinr * sinp * siny,
		sinr * cosp * cosy - cosr * sinp * siny,
		cosr * sinp * cosy + sinr * cosp * siny,
		cosr * cosp * siny - sinr * sinp * cosy);
end

---
-- Get the length of the quaternion.
-- @return number The length of the quaternion.
--
function QUATERNION:Length()
	return math.sqrt(self.w * self.w + self.x * self.x + self.y * self.y + self.z * self.z);
end

---
-- Normalize the quaternion.
-- @return quaternion The normalized quaternion.
--
function QUATERNION:Normalize()
	local  len = self:Length();
	return len > 0 && self:DivScalar(len) || self;
end

---
-- Get the conjugate of the quaternion.
-- @return quaternion The conjugated quaternion.
--
function QUATERNION:Conjugate()
	return self:Set(self.w, -self.x, -self.y, -self.z);
end

---
-- Invert the quaternion.
-- @return quaternion The inverted quaternion.
--
function QUATERNION:Invert()
	return self:Conjugate():Normalize();
end

function QUATERNION:__unm()
	return self:Negated();
end

---
-- Multiply the quaternion by a scalar value.
-- @param  scalar The scalar value to multiply by.
-- @return quaternion The modified quaternion after multiplication.
--
function QUATERNION:MulScalar(scalar)
	return self:Set(self.w * scalar, self.x * scalar, self.y * scalar, self.z * scalar);
end

---
-- Multiply this quaternion by another quaternion.
-- @param  q The quaternion to multiply by.
-- @return quaternion The modified quaternion after multiplication.
--
function QUATERNION:Mul(q)

	local qw, qx, qy, qz = self:Unpack();
	local q2w, q2x, q2y, q2z = q:Unpack();

	return self:Set(
		qw * q2w - qx * q2x - qy * q2y - qz * q2z,
		qx * q2w + qw * q2x + qy * q2z - qz * q2y,
		qy * q2w + qw * q2y + qz * q2x - qx * q2z,
		qz * q2w + qw * q2z + qx * q2y - qy * q2x);
end

function QUATERNION:__mul(q)
	return IsQuaternion(q) && Quaternion(self):Mul(q) || Quaternion(self):MulScalar(q);
end

function QUATERNION:__concat(q)
	return Quaternion(q):Mul(self);
end

---
-- Converts the quaternion to an angle-axis representation.
-- @return number The angle in degrees.
-- @return vector A 3D vector representing the axis.
--
function QUATERNION:AngleAxis()

	local qw  = self.w;
	local den = math.sqrt(1.0 - qw * qw);

	return math.deg(2.0 * math.acos(qw)), den > self.__epsl && (Vector(self.x, self.y, self.z) / den) || self.__axis;
end

---
-- Unpacks a quaternion into its components.
-- @return number The w component.
-- @return number The x component.
-- @return number The y component.
-- @return number The z component.
-- 
function QUATERNION:Unpack()
	return self.w, self.x, self.y, self.z;
end
