#!/usr/bin/env python3

from typing import Optional
import asyncio
from functools import wraps
from itertools import islice


def coro(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        return asyncio.run(f(*args, **kwargs))

    return wrapper


def generate_chunk(it, size):
    it = iter(it)
    return iter(lambda: tuple(islice(it, size)), ())


def coalesce(val: Optional[int], default: int = 0) -> int:
    return val if val else default
