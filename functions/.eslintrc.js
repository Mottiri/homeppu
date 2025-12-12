module.exports = {
    root: true,
    env: {
        es6: true,
        node: true,
    },
    extends: [
        "eslint:recommended",
        "plugin:import/errors",
        "plugin:import/warnings",
        "plugin:import/typescript",
        "google",
        "plugin:@typescript-eslint/recommended",
    ],
    parser: "@typescript-eslint/parser",
    parserOptions: {
        project: ["tsconfig.json"],
        sourceType: "module",
    },
    ignorePatterns: [
        "/lib/**/*", // Ignore built files.
    ],
    plugins: [
        "@typescript-eslint",
        "import",
    ],
    rules: {
        "quotes": ["error", "double"],
        "import/no-unresolved": 0,
        "indent": ["error", 2],
        "object-curly-spacing": "off",
        "max-len": ["off"],
        "@typescript-eslint/no-explicit-any": "off",
        "require-jsdoc": "off",
        "valid-jsdoc": "off",
        "@typescript-eslint/no-non-null-assertion": "off",
        "no-unused-vars": "off",
        "@typescript-eslint/no-unused-vars": "off",
        "camelcase": "off",
        "spaced-comment": "off",
        "no-trailing-spaces": "off",
        "eol-last": "off",
        "padded-blocks": "off",
        "no-multiple-empty-lines": "off",
        "object-curly-spacing": "off",
        "comma-dangle": "off",
        "arrow-parens": "off",
        "indent": "off",
        "quotes": "off",
        "prefer-const": "off"
    },
};
