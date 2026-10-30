package com.ledgerpay.wallet;

import java.security.MessageDigest;

public class Untested {
    public int add(int a, int b) { return a + b; }

    public byte[] weakHash(byte[] input) throws Exception {
        return MessageDigest.getInstance("MD5").digest(input);
    }
}
