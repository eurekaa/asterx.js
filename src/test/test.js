var $BACK_ERR = function (error) {
    var target = typeof window !== 'undefined' ? window : global;
    if (target.onError)
        return target.onError(error);
    else
        throw error;
};
(function () {
    var exist, fs, readme, readme2, test;
    fs = require('fs');
    test = function ($BACK) {
        try {
            var exist;
            return fs.exists('../readme.md', function (error, exist) {
                try {
                    if (error)
                        return $BACK ? $BACK(error) : $BACK_ERR(error);
                    return $BACK ? $BACK(null, exist) : exist;
                } catch (error) {
                    return $BACK ? $BACK(error) : $BACK_ERR(error);
                }
            });
        } catch (error) {
            return $BACK ? $BACK(error) : $BACK_ERR(error);
        }
    };
    return fs.exists('../readme.md', function (error, exist) {
        try {
            if (error)
                return $BACK ? $BACK(error) : $BACK_ERR(error);
            if (exist) {
                return fs.readFile('../readme.md', function (error, readme) {
                    try {
                        if (error)
                            return $BACK ? $BACK(error) : $BACK_ERR(error);
                        console.log(readme);
                    } catch (error) {
                        return $BACK ? $BACK(error) : $BACK_ERR(error);
                    }
                });
            }
            return fs.readFile('../readme.md', function (error, readme2) {
                try {
                    if (error)
                        return $BACK ? $BACK(error) : $BACK_ERR(error);
                } catch (error) {
                    return $BACK ? $BACK(error) : $BACK_ERR(error);
                }
            });
        } catch (error) {
            return $BACK ? $BACK(error) : $BACK_ERR(error);
        }
    });
}.call(this));
/*# sourceMappingURL=/test.js.map */