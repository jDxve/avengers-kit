// Exactly 6 errors. Each marked line must be flagged, and nothing else.
import React, { useState, useEffect, useId, useRef } from 'react';

export function Forbidden() {
  const [open] = useState(false); // FLAG
  useEffect(() => {}, []); // FLAG
  const [other] = React.useState(0); // FLAG
  const data = fetch('/orders'); // FLAG
  const token = localStorage.getItem('t'); // FLAG
  const href = window.location.href; // FLAG
  const id = useId();
  const ref = useRef(null);
  return [open, other, data, token, href, id, ref];
}
