#include <QFile>
#include <QJSEngine>
#include <QJSValue>
#include <QtTest>

class ApplicationSearchTests : public QObject
{
    Q_OBJECT

private:
    QJSEngine m_engine;

    QJSValue entry(const QString &name,
                   const QString &genericName = {},
                   const QStringList &keywords = {})
    {
        QJSValue value = m_engine.newObject();
        value.setProperty(QStringLiteral("name"), name);
        value.setProperty(QStringLiteral("genericName"), genericName);
        value.setProperty(QStringLiteral("comment"), QString());
        value.setProperty(QStringLiteral("id"), name.toLower());
        value.setProperty(QStringLiteral("startupClass"), QString());
        value.setProperty(QStringLiteral("categories"), m_engine.newArray());

        QJSValue keywordArray = m_engine.newArray(keywords.size());
        for (qsizetype index = 0; index < keywords.size(); ++index)
            keywordArray.setProperty(static_cast<quint32>(index), keywords.at(index));
        value.setProperty(QStringLiteral("keywords"), keywordArray);
        return value;
    }

    double score(const QJSValue &application, const QString &query)
    {
        const QJSValue function = m_engine.globalObject().property(QStringLiteral("applicationScore"));
        return function.call({application, query}).toNumber();
    }

private slots:
    void initTestCase()
    {
        QFile source(QStringLiteral(APPLICATION_SEARCH_SOURCE));
        QVERIFY2(source.open(QIODevice::ReadOnly | QIODevice::Text), qPrintable(source.errorString()));
        QString script = QString::fromUtf8(source.readAll());
        script.remove(QStringLiteral(".pragma library"));
        const QJSValue result = m_engine.evaluate(script, source.fileName());
        QVERIFY2(!result.isError(), qPrintable(result.toString()));
    }

    void ranksExactAndPrefixMatchesFirst()
    {
        const QJSValue firefox = entry(QStringLiteral("Firefox"));
        QVERIFY(score(firefox, QStringLiteral("firefox"))
                > score(firefox, QStringLiteral("fire")));
        QVERIFY(score(entry(QStringLiteral("Fire Tools")), QStringLiteral("fire"))
                > score(entry(QStringLiteral("Wildfire")), QStringLiteral("fire")));
    }

    void supportsWordInitialAndGapMatches()
    {
        QVERIFY(score(entry(QStringLiteral("Visual Studio Code")), QStringLiteral("vsc")) > 0);
        QVERIFY(score(entry(QStringLiteral("Firefox")), QStringLiteral("frfx")) > 0);
        QCOMPARE(score(entry(QStringLiteral("Firefox")), QStringLiteral("zfx")), -1.0);
    }

    void requiresEveryQueryToken()
    {
        const QJSValue code = entry(QStringLiteral("Visual Studio Code"));
        QVERIFY(score(code, QStringLiteral("visual code")) > 0);
        QCOMPARE(score(code, QStringLiteral("visual browser")), -1.0);
    }

    void weightsNameAboveMetadata()
    {
        const double nameMatch = score(entry(QStringLiteral("Terminal")), QStringLiteral("terminal"));
        const double keywordMatch = score(
            entry(QStringLiteral("Console"), {}, {QStringLiteral("terminal")}),
            QStringLiteral("terminal"));
        QVERIFY(nameMatch > keywordMatch);
    }

    void normalizesCaseSeparatorsAndAccents()
    {
        QVERIFY(score(entry(QStringLiteral("Visual-Studio Code")), QStringLiteral("studio code")) > 0);
        QVERIFY(score(entry(QStringLiteral("Café")), QStringLiteral("cafe")) > 0);
    }
};

QTEST_MAIN(ApplicationSearchTests)
#include "application_search_tests.moc"
