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
	__axis = Vector()
}

QUATERNION.__index = QUATERNION

local setmetatable = setmetatable
local getmetatable = getmetatable
local math = math

---
-- Create a new quaternion.
-- If a single argument 'w' is provided, it assumes a quaternion object was passed in to copy the
-- values from. If 'w' and 'x', 'y', and 'z' are provided, it creates a quaternion with the provided values.
-- @param  q Quaternion object to copy.
-- @return quaternion A new quaternion.
--
local function Quaternion(q)
	return setmetatable({ w = q.w, x = q.x, y = q.y, z = q.z }, QUATERNION)
end

---
-- Create a new quaternion.
-- If a single argument 'w' is provided, it assumes a quaternion object was passed in to copy the
-- values from. If 'w' and 'x', 'y', and 'z' are provided, it creates a quaternion with the provided values.
-- @param  q Quaternion object to copy.
-- @return quaternion A new quaternion.
--
function QuaternionFromAngle(ang)
	local p    = math.rad(ang.p) * 0.5
	local y    = math.rad(ang.y) * 0.5
	local r    = math.rad(ang.r) * 0.5
	local sinp = math.sin(p)
	local cosp = math.cos(p)
	local siny = math.sin(y)
	local cosy = math.cos(y)
	local sinr = math.sin(r)
	local cosr = math.cos(r)

	return setmetatable({
		w = cosr * cosp * cosy + sinr * sinp * siny,
		x = sinr * cosp * cosy - cosr * sinp * siny,
		y = cosr * sinp * cosy + sinr * cosp * siny,
		z = cosr * cosp * siny - sinr * sinp * cosy
	}, QUATERNION)
end

---
-- Get the length of the quaternion.
-- @return number The length of the quaternion.
--
function QUATERNION:Length()
	return math.sqrt(self.w * self.w + self.x * self.x + self.y * self.y + self.z * self.z)
end

---
-- Normalize the quaternion.
-- @return quaternion The normalized quaternion.
--
function QUATERNION:Normalize()
	local len = self:Length()
	if len > 0 then self:DivScalar(len) end
end

---
-- Invert the quaternion.
-- @return quaternion The inverted quaternion.
--
function QUATERNION:Invert()
	self.x, self.y, self.z = -self.x, -self.y, -self.z
	self:Normalize()
end

---
-- Multiply the quaternion by a scalar value.
-- @param  scalar The scalar value to multiply by.
-- @return quaternion The modified quaternion after multiplication.
--
function QUATERNION:MulScalar(scalar)
	self.w, self.x, self.y, self.z = self.w * scalar, self.x * scalar, self.y * scalar, self.z * scalar
end

---
-- Multiply this quaternion by another quaternion.
-- @param  q The quaternion to multiply by.
-- @return quaternion The modified quaternion after multiplication.
--
function QUATERNION:Mul(q)
	local qw, qx, qy, qz = self.w, self.x, self.y, self.z
	local q2w, q2x, q2y, q2z = q.w, q.x, q.y, q.z
	self.w = qw * q2w - qx * q2x - qy * q2y - qz * q2z
	self.x = qx * q2w + qw * q2x + qy * q2z - qz * q2y
	self.y = qy * q2w + qw * q2y + qz * q2x - qx * q2z
	self.z = qz * q2w + qw * q2z + qx * q2y - qy * q2x
end

---
-- Divide the quaternion by a scalar value.
-- @param  scalar The scalar value to divide by.
-- @return quaternion The modified quaternion after division.
--
function QUATERNION:DivScalar(scalar)
	self:MulScalar(1.0 / scalar)
end

---
-- Converts the quaternion to an angle-axis representation.
-- @return number The angle in degrees.
-- @return vector A 3D vector representing the axis.
--
function QUATERNION:AngleAxis()
	local qw = self.w
	local den = math.sqrt(1.0 - qw * qw)

	return math.deg(2.0 * math.acos(qw)), den > self.__epsl && (Vector(self.x, self.y, self.z) / den) || self.__axis
end
